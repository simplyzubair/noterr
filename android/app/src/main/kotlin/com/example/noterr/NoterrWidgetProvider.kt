package com.example.noterr

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews

class NoterrTodoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray
        ) {
            val widgetData = context.getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
            appWidgetIds.forEach { widgetId ->
                val views = RemoteViews(context.packageName, R.layout.noterr_todo_widget)
                views.setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("todo_title", "Today To Do")
                )
                views.setTextViewText(
                    R.id.widget_body,
                    widgetData.getString("todo_body", "No tasks yet")
                )
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundColor",
                    parseWidgetColor(widgetData.getString("todo_color", "E7F6EF"), "#E7F6EF")
                )
                views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }
    }
}

class NoterrStickyWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray
        ) {
            val widgetData = context.getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
            appWidgetIds.forEach { widgetId ->
                val views = RemoteViews(context.packageName, R.layout.noterr_sticky_widget)
                views.setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("sticky_title", "Sticky Notes")
                )
                views.setTextViewText(
                    R.id.widget_body,
                    widgetData.getString("sticky_body", "No sticky notes yet")
                )
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundColor",
                    parseWidgetColor(widgetData.getString("sticky_color", "FFF4B8"), "#FFF4B8")
                )
                views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }
    }
}

private fun parseWidgetColor(hex: String?, fallback: String): Int {
    val normalized = hex?.trim()?.removePrefix("#") ?: fallback.removePrefix("#")
    return try {
        Color.parseColor("#$normalized")
    } catch (_: IllegalArgumentException) {
        Color.parseColor(fallback)
    }
}

private fun openAppIntent(context: Context): PendingIntent {
    val intent = Intent(context, MainActivity::class.java)
    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    return PendingIntent.getActivity(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
}
