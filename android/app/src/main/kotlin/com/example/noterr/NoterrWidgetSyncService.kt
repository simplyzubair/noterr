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
                2,
                30,
                TimeUnit.SECONDS
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
        val supabaseUrl = prefs.getString("supabase_url", "")?.trim().orEmpty()
        val anonKey = prefs.getString("supabase_anon_key", "")?.trim().orEmpty()
        val passphrase = prefs.getString("passphrase", "")?.trim().orEmpty()
        if (supabaseUrl.isEmpty() || anonKey.isEmpty() || passphrase.isEmpty()) return

        val credentials = syncCredentials(passphrase)
        val auth = postJson(
            "$supabaseUrl/auth/v1/token?grant_type=password",
            anonKey,
            null,
            JSONObject()
                .put("email", credentials.first)
                .put("password", credentials.second)
        )
        val accessToken = auth.optString("access_token")
        val userId = auth.optJSONObject("user")?.optString("id").orEmpty()
        if (accessToken.isEmpty() || userId.isEmpty()) return

        val profileRows = getArray(
            "$supabaseUrl/rest/v1/noterr_profiles?select=vault_salt&user_id=eq.$userId&limit=1",
            anonKey,
            accessToken
        )
        if (profileRows.length() == 0) return
        val salt = profileRows.getJSONObject(0).optString("vault_salt")
        if (salt.isEmpty()) return
        val vaultKey = deriveVaultKey(passphrase, salt)

        val rows = getArray(
            "$supabaseUrl/rest/v1/noterr_notes?select=*&owner_id=eq.$userId&order=updated_at.desc",
            anonKey,
            accessToken
        )

        var selected: JSONObject? = null
        for (index in 0 until rows.length()) {
            val row = rows.getJSONObject(index)
            val note = decryptNote(row, vaultKey)
            if (note.optBoolean("isDeleted", false)) continue
            if (note.optBoolean("isArchived", false)) continue
            if (note.optString("boardName") != "Today") continue
            if (!note.optBoolean("showOnMobileWidget", true)) continue
            selected = note
            break
        }
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
            .putString("colorHex", selected.optString("colorHex", "F2F2F2"))
            .putFloat("opacity", selected.optDouble("opacity", 1.0).toFloat())
            .apply()

        updateHomeWidgets()
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
        val parts = mutableListOf<String>()
        val body = note.optString("body").trim()
        if (body.isNotEmpty()) parts.add(body)
        val checklist = note.optJSONArray("checklist") ?: JSONArray()
        val taskLines = mutableListOf<String>()
        for (index in 0 until checklist.length()) {
            val item = checklist.getJSONObject(index)
            val text = item.optString("text").trim()
            if (text.isEmpty()) continue
            val carried = if (item.has("carriedFrom") && !item.isNull("carriedFrom")) " (carried)" else ""
            taskLines.add(
                if (item.optBoolean("done", false)) {
                    "[x] $text$carried"
                } else if (item.optBoolean("isFocus", false)) {
                    "NOW: $text$carried"
                } else {
                    "- $text$carried"
                }
            )
        }
        if (taskLines.isNotEmpty()) parts.add(taskLines.joinToString("\n"))
        val content = if (parts.isEmpty()) "No notes or tasks yet" else parts.joinToString("\n\n")
        return "${dailyQuote()}\n\n$content"
    }

    private fun dailyQuote(): String {
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
            "Quran 94:5 - With hardship comes ease; keep moving.",
            "Quran 2:153 - Seek help through patience and prayer.",
            "Quran 14:7 - Gratitude opens the door to increase.",
            "Quran 53:39 - You gain from what you strive for.",
            "Quran 13:11 - Change begins with what is within you.",
            "Quran 3:159 - Decide, then trust Allah.",
            "Quran 65:3 - Trust Allah; He is enough.",
            "Quran 39:10 - The patient are rewarded beyond measure.",
            "Quran 11:88 - Success is only through Allah.",
            "Quran 29:69 - Strive sincerely; guidance opens.",
            "Quran 103:3 - Faith, good work, truth, and patience.",
            "Quran 16:127 - Be patient; your patience is from Allah.",
            "Quran 20:114 - Ask for increase in knowledge.",
            "Quran 17:84 - Work according to your way; improve it.",
            "Quran 23:1 - Focus and humility lead to success.",
            "Quran 24:38 - Allah rewards the best of your actions.",
            "Quran 67:15 - Walk the earth and seek provision.",
            "Quran 73:8 - Remember your Lord and devote yourself.",
            "Quran 76:9 - Serve with sincerity, not applause.",
            "Quran 87:8 - The right path can be made easy.",
            "Sabr is strength under control.",
            "Shukr turns today's work into worship.",
            "Make effort, then leave the outcome to Allah.",
            "Good work begins with a clean intention.",
            "A grateful heart works with lighter hands.",
            "Patience is not delay; it is steady movement.",
            "Barakah grows where focus and honesty meet.",
            "Do the task with ihsan: quietly, fully, well.",
            "Trust Allah, then do your part properly.",
            "Let your work be useful, sincere, and steady."
        )
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val day = calendar.timeInMillis / 86_400_000L
        return quotes[(day % quotes.size).toInt()]
    }

    private fun syncCredentials(passphrase: String): Pair<String, String> {
        val emailBytes = sha256("noterr-sync-email:v1:$passphrase")
        val passwordBytes = sha256("noterr-sync-password:v1:$passphrase")
        val emailId = emailBytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }.substring(0, 40)
        val password = Base64.encodeToString(passwordBytes, Base64.URL_SAFE or Base64.NO_WRAP)
        return "vault-$emailId@noterr.local" to "Noterr-$password"
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

    private fun postJson(url: String, anonKey: String, token: String?, body: JSONObject): JSONObject {
        val connection = openConnection(url, anonKey, token, "POST")
        OutputStreamWriter(connection.outputStream).use { it.write(body.toString()) }
        return JSONObject(readResponse(connection))
    }

    private fun getArray(url: String, anonKey: String, token: String): JSONArray {
        val connection = openConnection(url, anonKey, token, "GET")
        return JSONArray(readResponse(connection))
    }

    private fun openConnection(
        url: String,
        anonKey: String,
        token: String?,
        method: String
    ): HttpURLConnection {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.setRequestProperty("apikey", anonKey)
        connection.setRequestProperty("Content-Type", "application/json")
        if (token != null) connection.setRequestProperty("Authorization", "Bearer $token")
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
