package com.example.noterr

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.widget.RemoteViews

class NoterrWidgetProvider : AppWidgetProvider() {
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
                val views = RemoteViews(context.packageName, R.layout.noterr_widget)
                views.setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("title", "Today")
                )
                views.setTextViewText(
                    R.id.widget_body,
                    styledBody(widgetData.getString("body", "No notes or tasks yet") ?: "No notes or tasks yet")
                )
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundColor",
                    parseWidgetColor(
                        widgetData.getString("colorHex", "F2F2F2"),
                        "#F2F2F2",
                        widgetData.getFloat("opacity", 1f)
                    )
                )
                views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }
    }
}

private fun styledBody(raw: String): SpannableString {
    val output = StringBuilder()
    val doneRanges = mutableListOf<Pair<Int, Int>>()
    raw.lines().forEachIndexed { index, line ->
        if (index > 0) output.append('\n')
        if (line.startsWith("[x] ")) {
            val start = output.length
            output.append(line.removePrefix("[x] "))
            doneRanges.add(start to output.length)
        } else {
            output.append(line)
        }
    }
    val styled = SpannableString(output.toString())
    doneRanges.forEach { (start, end) ->
        if (end > start) {
            styled.setSpan(StrikethroughSpan(), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }
    return styled
}

private fun parseWidgetColor(hex: String?, fallback: String, opacity: Float): Int {
    val normalized = hex?.trim()?.removePrefix("#") ?: fallback.removePrefix("#")
    val color = try {
        Color.parseColor("#$normalized")
    } catch (_: IllegalArgumentException) {
        Color.parseColor(fallback)
    }
    return Color.argb(
        (opacity.coerceIn(0.45f, 1f) * 255).toInt(),
        Color.red(color),
        Color.green(color),
        Color.blue(color)
    )
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
