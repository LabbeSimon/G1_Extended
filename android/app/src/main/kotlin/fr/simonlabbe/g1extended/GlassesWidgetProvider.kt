package fr.simonlabbe.g1extended

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The home screen tile: battery, connection, and one action.
 *
 * Everything here is drawn from data the Dart side saved — the provider never
 * computes state of its own, because a widget that reasons independently of
 * the app is a widget that can contradict it.
 */
class GlassesWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val connected = widgetData.getBoolean("connected", false)
        val left = widgetData.getInt("left", -1)
        val right = widgetData.getInt("right", -1)
        val casePct = widgetData.getInt("case_pct", -1)
        val speedOn = widgetData.getBoolean("speed_on", false)
        val stamp = widgetData.getString("stamp", null)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_glasses)

            views.setTextViewText(R.id.widget_main, mainLine(connected, left, right))
            views.setTextViewText(R.id.widget_sub, subLine(connected, casePct, stamp))

            if (connected) {
                // The action follows the state it will change, so "SPEED ON"
                // means the speedometer is on, and tapping turns it off.
                views.setTextViewText(R.id.widget_action, if (speedOn) "SPEED ON" else "SPEED OFF")
                views.setInt(
                    R.id.widget_action, "setBackgroundResource",
                    if (speedOn) R.drawable.widget_action_on else R.drawable.widget_action_off,
                )
                views.setTextColor(
                    R.id.widget_action,
                    if (speedOn) 0xFF1C1C1E.toInt() else 0xFFF5F5F7.toInt(),
                )
                views.setOnClickPendingIntent(
                    R.id.widget_action,
                    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("g1x://speed")),
                )
            } else {
                views.setTextViewText(R.id.widget_action, "RECONNECT")
                views.setInt(R.id.widget_action, "setBackgroundResource", R.drawable.widget_action_off)
                views.setTextColor(R.id.widget_action, 0xFFF5F5F7.toInt())
                views.setOnClickPendingIntent(
                    R.id.widget_action,
                    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("g1x://reconnect")),
                )
            }

            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun mainLine(connected: Boolean, left: Int, right: Int): String {
        if (!connected) return "Disconnected"

        // The same rule as the in-app gauge (battery_gauge.dart,
        // splitThreshold): one number when the sides agree, both when the gap
        // is worth knowing about — and when only one is shown, it is always
        // the emptier side, because that is the one that ends the day.
        val gapWorthShowing = 10
        return when {
            left >= 0 && right >= 0 && Math.abs(left - right) >= gapWorthShowing ->
                "L $left · R $right"
            left >= 0 && right >= 0 -> "${minOf(left, right)}%"
            left >= 0 -> "$left%"
            right >= 0 -> "$right%"
            else -> "—"
        }
    }

    private fun subLine(connected: Boolean, casePct: Int, stamp: String?): String {
        if (!connected) return "Tap to open · button to reconnect"

        val parts = mutableListOf<String>()
        if (casePct >= 0) parts.add("case $casePct%")
        if (stamp != null) parts.add(stamp)
        return if (parts.isEmpty()) "Connected" else parts.joinToString("  ·  ")
    }
}
