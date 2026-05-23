package com.example.noterr

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
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
            if (call.method != "publish") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val prefs = getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("title", call.argument<String>("title") ?: "Noterr")
                .putString("body", call.argument<String>("body") ?: "No active notes")
                .putString("todo_title", call.argument<String>("todoTitle") ?: "Today To Do")
                .putString("todo_body", call.argument<String>("todoBody") ?: "No tasks yet")
                .putString("todo_color", call.argument<String>("todoColorHex") ?: "E7F6EF")
                .putString("sticky_title", call.argument<String>("stickyTitle") ?: "Sticky Notes")
                .putString("sticky_body", call.argument<String>("stickyBody") ?: "No sticky notes yet")
                .putString("sticky_color", call.argument<String>("stickyColorHex") ?: "FFF4B8")
                .apply()

            val manager = AppWidgetManager.getInstance(this)
            NoterrTodoWidgetProvider.updateWidgets(
                this,
                manager,
                manager.getAppWidgetIds(ComponentName(this, NoterrTodoWidgetProvider::class.java))
            )
            NoterrStickyWidgetProvider.updateWidgets(
                this,
                manager,
                manager.getAppWidgetIds(ComponentName(this, NoterrStickyWidgetProvider::class.java))
            )
            result.success(null)
        }
    }
}
