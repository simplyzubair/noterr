package com.example.noterr

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "noterr/updater"
        ).setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank() || !File(path).exists()) {
                result.error("missing", "Downloaded update not found", null)
                return@setMethodCallHandler
            }
            // Android 8+ asks once per app for "Install unknown apps". Send the
            // user to that switch; the Dart side retries after they come back.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success("needs_permission")
                return@setMethodCallHandler
            }
            try {
                val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
                startActivity(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_ACTIVITY_NEW_TASK
                        )
                )
                result.success("started")
            } catch (error: Throwable) {
                Log.w("Noterr", "Could not start the installer", error)
                result.error("install_failed", error.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "noterr/widget"
        ).setMethodCallHandler { call, result ->
            if (call.method == "configureLiveWidgetSync") {
                getSharedPreferences("noterr_live_widget_sync", Context.MODE_PRIVATE)
                    .edit()
                    .putString("sync_url", call.argument<String>("syncUrl") ?: "")
                    .putString("passphrase", call.argument<String>("passphrase") ?: "")
                    .putString("vault_salt", call.argument<String>("vaultSalt") ?: "")
                    .apply()
                try {
                    val intent = Intent(this, NoterrWidgetSyncService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                } catch (error: Throwable) {
                    Log.w("Noterr", "Live widget sync service could not start", error)
                }
                result.success(null)
                return@setMethodCallHandler
            }

            if (call.method != "publish") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val prefs = getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("title", call.argument<String>("title") ?: "Noterr")
                .putString("body", call.argument<String>("body") ?: "No notes or tasks yet")
                .putString("tasks_body", call.argument<String>("todoBody") ?: "No tasks yet")
                .putString("colorHex", "F2F2F2")
                .putFloat("opacity", 1.0f)
                .putString("todo_title", call.argument<String>("todoTitle") ?: "Today To Do")
                .putString("todo_body", call.argument<String>("todoBody") ?: "No tasks yet")
                .putString("todo_color", call.argument<String>("todoColorHex") ?: "E7F6EF")
                .putFloat("todo_opacity", (call.argument<Double>("todoOpacity") ?: 1.0).toFloat())
                .putString("sticky_title", call.argument<String>("stickyTitle") ?: "Sticky Notes")
                .putString("sticky_body", call.argument<String>("stickyBody") ?: "No sticky notes yet")
                .putString("sticky_color", call.argument<String>("stickyColorHex") ?: "FFF4B8")
                .putFloat("sticky_opacity", (call.argument<Double>("stickyOpacity") ?: 1.0).toFloat())
                .apply()

            val manager = AppWidgetManager.getInstance(this)
            NoterrWidgetProvider.updateWidgets(
                this,
                manager,
                manager.getAppWidgetIds(ComponentName(this, NoterrWidgetProvider::class.java))
            )
            result.success(null)
        }
    }
}
