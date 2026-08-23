package fr.simonlabbe.g1extended

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * A row of actions on the home screen: write a note, start captions,
 * silence the display.
 *
 * Separate from the status tile rather than crowded into it. That one
 * answers "how are my glasses"; this one answers "do the thing" — and a
 * single widget trying to be both would give each half too little room to
 * be read at a glance, which is the only thing a home screen widget is for.
 *
 * Note and captions open the app on the right screen, because both need
 * one. Silent is done where it is tapped: sending a toggle through a launch
 * would make the simplest action the slowest.
 */
class ActionsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetPlugin.getData(context)
        val silent = data.getBoolean("silent_on", false)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_actions)

            views.setOnClickPendingIntent(
                R.id.action_note,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("g1x://note"),
                ),
            )
            views.setOnClickPendingIntent(
                R.id.action_captions,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("g1x://captions"),
                ),
            )

            // The label names the state, not the verb — "SILENT ON" means it
            // is on, the same rule the status tile's button follows.
            views.setTextViewText(R.id.action_silent, if (silent) "SILENT ON" else "SILENT")
            views.setInt(
                R.id.action_silent, "setBackgroundResource",
                if (silent) R.drawable.widget_action_on else R.drawable.widget_action_off,
            )
            views.setTextColor(
                R.id.action_silent,
                if (silent) 0xFF1C1C1E.toInt() else 0xFFF5F5F7.toInt(),
            )
            views.setOnClickPendingIntent(
                R.id.action_silent,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("g1x://silent")),
            )

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
