package com.example.noterr

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
