package com.example.noterr

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Base64
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

class NoterrWidgetSyncWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {
    override fun doWork(): Result {
        return try {
            refreshWidget()
            schedule(applicationContext)
            Result.success()
        } catch (_: Exception) {
            schedule(applicationContext)
            Result.retry()
        }
    }

    private fun refreshWidget() {
        val prefs = applicationContext.getSharedPreferences("noterr_background_sync", Context.MODE_PRIVATE)
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
            selected = note
            break
        }
        if (selected == null) return

        val widgetPrefs = applicationContext.getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
        widgetPrefs.edit()
            .putString("title", selected.optString("title", "Today"))
            .putString("body", dailyBody(selected))
            .putString("colorHex", selected.optString("colorHex", "F2F2F2"))
            .putFloat("opacity", selected.optDouble("opacity", 1.0).toFloat())
            .apply()

        val manager = AppWidgetManager.getInstance(applicationContext)
        NoterrWidgetProvider.updateWidgets(
            applicationContext,
            manager,
            manager.getAppWidgetIds(ComponentName(applicationContext, NoterrWidgetProvider::class.java))
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
            taskLines.add(if (item.optBoolean("done", false)) "[x] $text" else "- $text")
        }
        if (taskLines.isNotEmpty()) parts.add(taskLines.joinToString("\n"))
        return if (parts.isEmpty()) "No notes or tasks yet" else parts.joinToString("\n\n")
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
        if (connection.responseCode !in 200..299) {
            throw IllegalStateException(text)
        }
        return text
    }

    companion object {
        private const val UNIQUE_WORK = "noterr_widget_sync"

        fun schedule(context: Context) {
            val request = OneTimeWorkRequestBuilder<NoterrWidgetSyncWorker>()
                .setInitialDelay(2, TimeUnit.MINUTES)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                UNIQUE_WORK,
                ExistingWorkPolicy.REPLACE,
                request
            )
        }
    }
}
