package com.example.noterr

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.widget.RemoteViews
import java.util.Calendar

class NoterrWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_QUOTE_TICK) {
            val manager = AppWidgetManager.getInstance(context)
            updateWidgets(
                context,
                manager,
                manager.getAppWidgetIds(ComponentName(context, NoterrWidgetProvider::class.java))
            )
        }
        scheduleNextQuoteTick(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
        scheduleNextQuoteTick(context)
    }

    companion object {
        private const val ACTION_QUOTE_TICK = "com.example.noterr.QUOTE_TICK"

        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray
        ) {
            val widgetData = context.getSharedPreferences("noterr_widget", Context.MODE_PRIVATE)
            appWidgetIds.forEach { widgetId ->
                val views = RemoteViews(context.packageName, R.layout.noterr_widget)
                val tasks = widgetData.getString("tasks_body", null)
                    ?: widgetData.getString("todo_body", null)
                    ?: "No tasks yet"
                views.setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("title", "Today")
                )
                views.setTextViewText(
                    R.id.widget_body,
                    styledBody("${noterrDailyPrompt()}\n\n$tasks")
                )
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundColor",
                    Color.parseColor("#F2F2F2")
                )
                views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }

        private fun scheduleNextQuoteTick(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, NoterrWidgetProvider::class.java).apply {
                action = ACTION_QUOTE_TICK
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                240525,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC,
                nextSixHourBoundaryMillis(),
                pendingIntent
            )
        }

        private fun nextSixHourBoundaryMillis(): Long {
            val calendar = Calendar.getInstance()
            val currentHour = calendar.get(Calendar.HOUR_OF_DAY)
            val nextSlotHour = ((currentHour / 6) + 1) * 6
            if (nextSlotHour >= 24) {
                calendar.add(Calendar.DAY_OF_YEAR, 1)
                calendar.set(Calendar.HOUR_OF_DAY, 0)
            } else {
                calendar.set(Calendar.HOUR_OF_DAY, nextSlotHour)
            }
            calendar.set(Calendar.MINUTE, 0)
            calendar.set(Calendar.SECOND, 5)
            calendar.set(Calendar.MILLISECOND, 0)
            return calendar.timeInMillis
        }
    }
}

fun noterrDailyPrompt(): String {
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
