package com.example.noterr

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Calendar
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

class NoterrWidgetSyncService : Service() {
    private var executor: ScheduledExecutorService? = null
    private var canRunForeground = false

    override fun onCreate() {
        super.onCreate()
        try {
            createNotificationChannel()
            startForeground(NOTIFICATION_ID, notification())
            canRunForeground = true
        } catch (error: Throwable) {
            Log.w("Noterr", "Live widget sync disabled because foreground service failed", error)
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!canRunForeground) return START_NOT_STICKY
        if (executor?.isShutdown != false) {
            executor = Executors.newSingleThreadScheduledExecutor()
            executor?.scheduleWithFixedDelay(
                { refreshWidgetSafely() },
                15,
                3,
                TimeUnit.MINUTES
            )
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        executor?.shutdownNow()
        executor = null
        super.onDestroy()
    }

    private fun refreshWidgetSafely() {
        try {
            refreshWidget()
        } catch (_: Exception) {
            // Keep the foreground service alive; the next interval retries.
        }
    }

    private fun refreshWidget() {
        val prefs = getSharedPreferences("noterr_live_widget_sync", Context.MODE_PRIVATE)
        val syncUrl = prefs.getString("sync_url", "")?.trim()?.trimEnd('/') ?: ""
        val passphrase = prefs.getString("passphrase", "")?.trim().orEmpty()
        if (syncUrl.isEmpty() || passphrase.isEmpty()) return

        val syncId = syncId(passphrase)
        var salt = prefs.getString("vault_salt", "")?.trim().orEmpty()
        if (salt.isEmpty()) {
            val auth = postJson(
                "$syncUrl/profile",
                JSONObject()
                    .put("syncId", syncId)
            )
            salt = auth.optString("vaultSalt")
            if (salt.isNotEmpty()) {
                prefs.edit().putString("vault_salt", salt).apply()
            }
        }
        if (salt.isEmpty()) return
        val vaultKey = deriveVaultKey(passphrase, salt)

        val pull = postJson(
            "$syncUrl/pull",
            JSONObject().put("syncId", syncId)
        )
        val rows = pull.optJSONArray("notes") ?: JSONArray()

        val todayNotes = mutableListOf<JSONObject>()
        for (index in 0 until rows.length()) {
            val row = rows.getJSONObject(index)
            val note = decryptNote(row, vaultKey)
            if (note.optBoolean("isDeleted", false)) continue
            if (note.optBoolean("isArchived", false)) continue
            if (note.optString("boardName") != "Today") continue
            if (!note.optBoolean("showOnMobileWidget", true)) continue
            todayNotes.add(note)
        }
        val selected = unifiedTodayNote(todayNotes)
        if (selected == null) {
            getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
                .edit()
                .putString("title", "Noterr")
                .putString("body", "${dailyQuote()}\n\nNo active notes")
                .putString("colorHex", "F2F2F2")
                .putFloat("opacity", 1f)
                .apply()
            updateHomeWidgets()
            return
        }

        getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
            .edit()
            .putString("title", selected.optString("title", "Today"))
            .putString("body", dailyBody(selected))
            .putString("colorHex", "F2F2F2")
            .putFloat("opacity", 1f)
            .apply()

        updateHomeWidgets()
    }

    private fun unifiedTodayNote(notes: List<JSONObject>): JSONObject? {
        if (notes.isEmpty()) return null
        if (notes.size == 1) return notes.first()

        val base = JSONObject(notes.first().toString())
        val seenBodies = linkedSetOf<String>()
        val bodyParts = mutableListOf<String>()
        val checklistByKey = linkedMapOf<String, JSONObject>()
        val deletedKeys = linkedSetOf<String>()
        val bodyClearedAt = notes
            .map { it.optString("bodyClearedAt").trim() }
            .filter { it.isNotEmpty() }
            .maxOrNull()

        val baseBody = notes.first().optString("body").trim()
        if (
            baseBody.isNotEmpty() &&
            !wasBodyClearedAfter(notes.first(), bodyClearedAt) &&
            seenBodies.add(baseBody.lowercase())
        ) {
            bodyParts.add(baseBody)
        }

        for (note in notes.drop(1)) {
            val deleted = note.optJSONArray("deletedChecklistItemKeys") ?: JSONArray()
            for (index in 0 until deleted.length()) {
                val key = deleted.optString(index).trim()
                if (key.isNotEmpty()) deletedKeys.add(key)
            }
            val body = note.optString("body").trim()
            if (
                body.isNotEmpty() &&
                !wasBodyClearedAfter(note, bodyClearedAt) &&
                seenBodies.add(body.lowercase())
            ) {
                bodyParts.add(body)
            }
        }

        for (note in notes) {
            val deleted = note.optJSONArray("deletedChecklistItemKeys") ?: JSONArray()
            for (index in 0 until deleted.length()) {
                val key = deleted.optString(index).trim()
                if (key.isNotEmpty()) deletedKeys.add(key)
            }
            val checklist = note.optJSONArray("checklist") ?: JSONArray()
            for (index in 0 until checklist.length()) {
                val item = checklist.getJSONObject(index)
                val text = item.optString("text").trim()
                if (text.isEmpty()) continue
                val keys = checklistItemKeys(item)
                if (keys.any { deletedKeys.contains(it) }) continue
                checklistByKey.putIfAbsent(keys.first(), item)
            }
        }

        base.put("body", bodyParts.joinToString("\n\n"))
        val mergedChecklist = JSONArray()
        checklistByKey.values.forEach { mergedChecklist.put(it) }
        base.put("checklist", mergedChecklist)
        return base
    }

    private fun wasBodyClearedAfter(note: JSONObject, marker: String?): Boolean {
        if (marker.isNullOrEmpty()) return false
        val updatedAt = note.optString("updatedAt").trim()
        if (updatedAt.isEmpty()) return false
        return updatedAt <= marker
    }

    private fun checklistItemKeys(item: JSONObject): List<String> {
        val text = item.optString("text").trim().lowercase()
        val id = item.optString("id").trim()
        val keys = mutableListOf<String>()
        if (text.isNotEmpty()) keys.add("text:$text")
        if (id.isNotEmpty()) keys.add("id:$id")
        return keys
    }

    private fun updateHomeWidgets() {
        val manager = AppWidgetManager.getInstance(this)
        NoterrWidgetProvider.updateWidgets(
            this,
            manager,
            manager.getAppWidgetIds(ComponentName(this, NoterrWidgetProvider::class.java))
        )
    }

    private fun decryptNote(row: JSONObject, key: ByteArray): JSONObject {
        val cipherText = Base64.decode(row.getString("encrypted_payload"), Base64.DEFAULT)
        val nonce = Base64.decode(row.getString("nonce"), Base64.DEFAULT)
        val mac = Base64.decode(row.getString("mac"), Base64.DEFAULT)
        val combined = cipherText + mac
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        return JSONObject(String(cipher.doFinal(combined), Charsets.UTF_8))
    }

    private fun dailyBody(note: JSONObject): String {
        val checklist = note.optJSONArray("checklist") ?: JSONArray()
        val taskLines = mutableListOf<String>()
        for (index in 0 until checklist.length()) {
            val item = checklist.getJSONObject(index)
            val text = item.optString("text").trim()
            if (text.isEmpty()) continue
            taskLines.add(
                if (item.optBoolean("done", false)) {
                    "[x] $text"
                } else if (item.optBoolean("isFocus", false)) {
                    "NOW: $text"
                } else {
                    "- $text"
                }
            )
        }
        val content = if (taskLines.isEmpty()) "No tasks yet" else taskLines.joinToString("\n")
        return "${dailyQuote()}\n\n$content"
    }

    private fun dailyQuote(): String {
        val ayahs = listOf(
            Triple("فَإِنَّ مَعَ الْعُسْرِ يُسْرًا", "Ash-Sharh 94:5", "With hardship comes ease."),
            Triple("وَاسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ", "Al-Baqarah 2:45", "Seek help through patience and prayer."),
            Triple("لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ", "Ibrahim 14:7", "If you are grateful, I will surely increase you."),
            Triple("وَأَن لَّيْسَ لِلْإِنسَانِ إِلَّا مَا سَعَى", "An-Najm 53:39", "A person gains from what they strive for."),
            Triple("إِنَّ اللَّهَ لَا يُغَيِّرُ مَا بِقَوْمٍ حَتَّىٰ يُغَيِّرُوا مَا بِأَنفُسِهِمْ", "Ar-Ra'd 13:11", "Allah changes a people when they change themselves."),
            Triple("فَإِذَا عَزَمْتَ فَتَوَكَّلْ عَلَى اللَّهِ", "Ali Imran 3:159", "When you decide, put your trust in Allah."),
            Triple("وَمَن يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ", "At-Talaq 65:3", "Whoever trusts Allah, He is enough for them."),
            Triple("إِنَّمَا يُوَفَّى الصَّابِرُونَ أَجْرَهُم بِغَيْرِ حِسَابٍ", "Az-Zumar 39:10", "The patient are rewarded without measure."),
            Triple("وَمَا تَوْفِيقِي إِلَّا بِاللَّهِ", "Hud 11:88", "My success is only through Allah."),
            Triple("وَالَّذِينَ جَاهَدُوا فِينَا لَنَهْدِيَنَّهُمْ سُبُلَنَا", "Al-Ankabut 29:69", "Those who strive sincerely are guided to the way."),
            Triple("وَتَوَاصَوْا بِالْحَقِّ وَتَوَاصَوْا بِالصَّبْرِ", "Al-Asr 103:3", "Hold to truth and encourage patience."),
            Triple("وَاصْبِرْ وَمَا صَبْرُكَ إِلَّا بِاللَّهِ", "An-Nahl 16:127", "Be patient; your patience is only through Allah."),
            Triple("رَّبِّ زِدْنِي عِلْمًا", "Ta-Ha 20:114", "My Lord, increase me in knowledge."),
            Triple("كُلٌّ يَعْمَلُ عَلَىٰ شَاكِلَتِهِ", "Al-Isra 17:84", "Each person works according to their way."),
            Triple("قَدْ أَفْلَحَ الْمُؤْمِنُونَ", "Al-Mu'minun 23:1", "Successful indeed are the believers."),
            Triple("لِيَجْزِيَهُمُ اللَّهُ أَحْسَنَ مَا عَمِلُوا", "An-Nur 24:38", "Allah rewards the best of what they did."),
            Triple("فَامْشُوا فِي مَنَاكِبِهَا وَكُلُوا مِن رِّزْقِهِ", "Al-Mulk 67:15", "Walk through the earth and seek His provision."),
            Triple("وَاذْكُرِ اسْمَ رَبِّكَ وَتَبَتَّلْ إِلَيْهِ تَبْتِيلًا", "Al-Muzzammil 73:8", "Remember your Lord and devote yourself to Him."),
            Triple("إِنَّمَا نُطْعِمُكُمْ لِوَجْهِ اللَّهِ", "Al-Insan 76:9", "Serve sincerely for the sake of Allah."),
            Triple("وَنُيَسِّرُكَ لِلْيُسْرَى", "Al-A'la 87:8", "We will ease you toward ease."),
            Triple("فَاذْكُرُونِي أَذْكُرْكُمْ", "Al-Baqarah 2:152", "Remember Me; I will remember you."),
            Triple("إِنَّ اللَّهَ مَعَ الصَّابِرِينَ", "Al-Baqarah 2:153", "Allah is with the patient."),
            Triple("وَعَسَىٰ أَن تَكْرَهُوا شَيْئًا وَهُوَ خَيْرٌ لَّكُمْ", "Al-Baqarah 2:216", "You may dislike something while it is good for you."),
            Triple("لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا", "Al-Baqarah 2:286", "Allah does not burden a soul beyond its capacity."),
            Triple("إِن تَنصُرُوا اللَّهَ يَنصُرْكُمْ وَيُثَبِّتْ أَقْدَامَكُمْ", "Muhammad 47:7", "Support Allah's cause; He supports you and steadies you."),
            Triple("وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مَخْرَجًا", "At-Talaq 65:2", "Whoever is mindful of Allah, He makes a way out."),
            Triple("سَيَجْعَلُ اللَّهُ بَعْدَ عُسْرٍ يُسْرًا", "At-Talaq 65:7", "Allah will bring ease after hardship."),
            Triple("إِنَّ مَعَ الْعُسْرِ يُسْرًا", "Ash-Sharh 94:6", "Surely, with hardship comes ease."),
            Triple("فَإِذَا فَرَغْتَ فَانصَبْ", "Ash-Sharh 94:7", "When you finish, rise to the next task."),
            Triple("وَإِلَىٰ رَبِّكَ فَارْغَب", "Ash-Sharh 94:8", "Turn your longing toward your Lord.")
        )
        val quotes = listOf(
            "Focus on the next right action.",
            "Small steps, done daily, become momentum.",
            "Protect your attention; it builds your life.",
            "Begin with gratitude. Continue with discipline.",
            "Clarity first, speed second.",
            "Do the useful thing before the urgent noise.",
            "A calm mind finishes better work.",
            "Today, simplify one thing.",
            "Progress is quiet before it is obvious.",
            "Let purpose choose your priorities.",
            "One completed task is better than ten worried thoughts.",
            "Work with intention, rest without guilt.",
            "Make the next step easy to start.",
            "Discipline is remembering what matters.",
            "Give your best attention to the present task.",
            "Peace grows where your actions match your values.",
            "Start small. Stay steady.",
            "Do less, but do it fully.",
            "Your future is built in today's habits.",
            "Write it down. Clear the mind.",
            "Consistency carries what motivation starts.",
            "Choose progress over perfection.",
            "Let the day have a direction.",
            "A focused hour can change the whole day.",
            "Be faithful with the work in front of you.",
            "Order outside begins with order inside.",
            "Finish the tiny promise.",
            "Less distraction, more devotion.",
            "Move with patience and purpose.",
            "The most important task deserves the quietest mind.",
            "Sabr is strength under control.",
            "Shukr turns today's work into worship.",
            "Make effort, then leave the outcome to Allah.",
            "Good work begins with a clean intention.",
            "A grateful heart works with lighter hands.",
            "Patience is not delay; it is steady movement.",
            "Barakah grows where focus and honesty meet.",
            "Do the task with ihsan: quietly, fully, well.",
            "Trust Allah, then do your part properly.",
            "Let your work be useful, sincere, and steady.",
            "A clear list turns worry into movement.",
            "Do the hard useful thing while your mind is fresh.",
            "Today does not need drama; it needs direction.",
            "Keep one promise to yourself before noon.",
            "The smallest finished task is real progress.",
            "Your attention is an amanah; spend it carefully.",
            "Make the next step so small that you can begin now.",
            "When motivation dips, return to routine.",
            "Strong days are built from honest minutes.",
            "Write it, do it, thank Allah for the ability.",
            "Do not chase every thought; choose the useful one.",
            "A quiet intention can carry heavy work.",
            "Reduce the list until action becomes obvious.",
            "The task in front of you is the doorway.",
            "Steady work beats anxious planning.",
            "Do one thing properly, then the next.",
            "Let your calendar reflect your values.",
            "Distraction is expensive; focus is barakah.",
            "Start before you feel ready.",
            "End the day with one clean completion."
        )
        val calendar = Calendar.getInstance()
        val slotHour = (calendar.get(Calendar.HOUR_OF_DAY) / 6) * 6
        calendar.set(Calendar.HOUR_OF_DAY, slotHour)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val slot = calendar.timeInMillis / 21_600_000L
        val index = if (slot < 0) -slot else slot
        val ayah = ayahs[(index % ayahs.size).toInt()]
        val quote = quotes[((index * 7) % quotes.size).toInt()]
        return "${ayah.first}\n${ayah.second} - ${ayah.third}\n$quote"
    }

    private fun syncId(passphrase: String): String {
        val emailBytes = sha256("noterr-sync-email:v1:$passphrase")
        return emailBytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }.substring(0, 40)
    }

    private fun deriveVaultKey(passphrase: String, salt: String): ByteArray {
        val spec = PBEKeySpec(
            passphrase.toCharArray(),
            Base64.decode(salt, Base64.DEFAULT),
            210000,
            256
        )
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }

    private fun sha256(value: String): ByteArray {
        return MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
    }

    private fun postJson(url: String, body: JSONObject): JSONObject {
        val connection = openConnection(url, "POST")
        OutputStreamWriter(connection.outputStream).use { it.write(body.toString()) }
        return JSONObject(readResponse(connection))
    }

    private fun openConnection(
        url: String,
        method: String
    ): HttpURLConnection {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.setRequestProperty("Content-Type", "application/json")
        if (method == "POST") connection.doOutput = true
        connection.connectTimeout = 15000
        connection.readTimeout = 15000
        return connection
    }

    private fun readResponse(connection: HttpURLConnection): String {
        val stream = if (connection.responseCode in 200..299) {
            connection.inputStream
        } else {
            connection.errorStream
        }
        val text = BufferedReader(stream.reader()).use { it.readText() }
        if (connection.responseCode !in 200..299) throw IllegalStateException(text)
        return text
    }

    private fun notification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Noterr live widget sync")
            .setContentText("Keeping your Daily Board widget updated")
            .setSmallIcon(R.drawable.ic_stat_noterr)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Noterr live sync",
            NotificationManager.IMPORTANCE_LOW
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "noterr_live_widget_sync"
        private const val NOTIFICATION_ID = 240524
    }
}
