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
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
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
        val planNotes = mutableListOf<JSONObject>()
        for (index in 0 until rows.length()) {
            val row = rows.getJSONObject(index)
            val note = decryptNote(row, vaultKey)
            if (note.optBoolean("isDeleted", false)) continue
            if (note.optString("boardName") == "Plans" && isPlanNote(note)) {
                planNotes.add(note)
                continue
            }
            if (note.optBoolean("isArchived", false)) continue
            if (note.optString("boardName") != "Today") continue
            if (!note.optBoolean("showOnMobileWidget", true)) continue
            todayNotes.add(note)
        }
        val selected = unifiedTodayNote(todayNotes)
        val todayLabel = SimpleDateFormat("d MMM yyyy", Locale.getDefault()).format(
            Calendar.getInstance().time
        )

        getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
            .edit()
            .putString("title", selected?.optString("title", todayLabel) ?: todayLabel)
            .putString("tasks_body", taskBody(selected, planNotes))
            .putString("colorHex", "F2F2F2")
            .putFloat("opacity", 1f)
            .apply()

        updateHomeWidgets()
    }

    private fun isPlanNote(note: JSONObject): Boolean {
        val tags = note.optJSONArray("tags") ?: return false
        for (index in 0 until tags.length()) {
            if (tags.optString(index) == "noterr-plan-v1") return true
        }
        return false
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

    private fun taskBody(note: JSONObject?, planNotes: List<JSONObject>): String {
        val taskLines = mutableListOf<String>()
        val seenTexts = linkedSetOf<String>()
        val existingPlanItems = linkedSetOf<String>()
        val deletedKeys = linkedSetOf<String>()
        if (note != null) {
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
                seenTexts.add(text.lowercase())
                val planId = item.optString("planId").trim()
                val planItemId = item.optString("planItemId").trim()
                if (planId.isNotEmpty() && planItemId.isNotEmpty()) {
                    existingPlanItems.add("$planId:$planItemId")
                }
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
        }

        val calendar = Calendar.getInstance()
        val todayIso = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(calendar.time)
        val todayCompact = SimpleDateFormat("yyyyMMdd", Locale.US).format(calendar.time)
        val weekday = ((calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        for (planNote in planNotes) {
            val plan = runCatching {
                JSONObject(planNote.optString("body"))
            }.getOrNull() ?: continue
            if (!plan.optBoolean("isActive", true)) continue
            val startDate = plan.optString("startDate")
            val endDate = plan.optString("endDate")
            if (startDate.isEmpty() || endDate.isEmpty()) continue
            if (todayIso < startDate || todayIso > endDate) continue
            val planId = plan.optString("id").trim()
            if (planId.isEmpty()) continue
            val items = plan.optJSONArray("items") ?: JSONArray()
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val kind = item.optString("kind")
                if (kind != "task" && kind != "habit") continue
                if (!isPlanItemDue(item, todayIso, weekday, calendar)) continue
                val text = item.optString("text").trim()
                val itemId = item.optString("id").trim()
                if (text.isEmpty() || itemId.isEmpty()) continue
                val planItemKey = "$planId:$itemId"
                val occurrenceId = "plan:$planId:$itemId:$todayCompact"
                if (existingPlanItems.contains(planItemKey)) continue
                if (deletedKeys.contains("id:$occurrenceId")) continue
                if (!seenTexts.add(text.lowercase())) continue
                taskLines.add("- $text")
            }
        }
        return if (taskLines.isEmpty()) "No tasks yet" else taskLines.joinToString("\n")
    }

    private fun isPlanItemDue(
        item: JSONObject,
        todayIso: String,
        weekday: Int,
        calendar: Calendar
    ): Boolean {
        val cadence = item.optString("cadence", "once")
        val scheduledDate = item.optString("scheduledDate").trim()
        val weekdays = item.optJSONArray("weekdays") ?: JSONArray()
        fun includesToday(): Boolean {
            for (index in 0 until weekdays.length()) {
                if (weekdays.optInt(index) == weekday) return true
            }
            return false
        }
        return when (cadence) {
            "daily" -> weekdays.length() == 0 || includesToday()
            "weekly" -> {
                if (weekdays.length() > 0) {
                    includesToday()
                } else {
                    scheduledDate.isNotEmpty() &&
                        weekdayForDate(scheduledDate) == weekday
                }
            }
            "monthly" -> {
                val anchorDay = scheduledDate.substringAfterLast('-').toIntOrNull()
                    ?: return false
                val targetDay = minOf(
                    anchorDay,
                    calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                )
                calendar.get(Calendar.DAY_OF_MONTH) == targetDay
            }
            else -> scheduledDate == todayIso
        }
    }

    private fun weekdayForDate(value: String): Int? {
        val parsed = runCatching {
            SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                isLenient = false
            }.parse(value)
        }.getOrNull() ?: return null
        val calendar = Calendar.getInstance().apply { time = parsed }
        return ((calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
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
