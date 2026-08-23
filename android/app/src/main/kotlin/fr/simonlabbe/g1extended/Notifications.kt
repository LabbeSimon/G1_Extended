package fr.simonlabbe.g1extended

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat

object Notifications {
    const val NOTIFICATION_ID_BACKGROUND_SERVICE = 1

    // Renamed alongside a change of importance. Android will not let an
    // existing channel's importance be lowered, so the only way to stop this
    // one behaving like an urgent alert is to create a different channel and
    // delete the old one.
    private const val CHANNEL_ID_BACKGROUND_SERVICE = "glasses_connection_native"
    private const val RETIRED_CHANNEL_ID = "background_service"

    fun createNotificationChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID_BACKGROUND_SERVICE,
                "G1 Extended",
                // Low: this is a permanent status line, not an alert. What
                // keeps the process alive is the foreground service type,
                // not this value.
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Maintains glasses connection and processes commands"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.deleteNotificationChannel(RETIRED_CHANNEL_ID)
            manager.createNotificationChannel(channel)
        }
    }

    fun buildForegroundNotification(context: Context): Notification {
        println("creating notification for background service");
        return NotificationCompat
            .Builder(context, CHANNEL_ID_BACKGROUND_SERVICE)
            .setSmallIcon(R.drawable.app_logo)
            .setContentTitle("G1 Extended")
            .setContentText("Maintaining glasses connection and processing commands.")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }
}