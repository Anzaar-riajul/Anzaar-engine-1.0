package com.techuboard.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Single, unified dynamic foreground notification manager for Techuboard Android.
 * Consolidates LAN Sync and Floating Hub into ONE clean, interactive notification.
 */
object TechuboardNotificationHelper {
    const val CHANNEL_ID = "techu_sync_foreground"
    const val NOTIFICATION_ID = 0x7101

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        // Clean up legacy separate hub channel if exists
        try {
            nm.deleteNotificationChannel("techu_floating_hub")
            nm.cancel(5567)
        } catch (_: Exception) {}

        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Techuboard Active Service",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows dynamic status of Techuboard sync and floating hub"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }
    }

    fun buildUnifiedNotification(context: Context): Notification {
        ensureChannel(context)

        val isHubActive = FloatingHubService.isRunning
        val isSyncActive = TechuboardSyncForegroundService.isRunning

        val openAppPending = SyncNotificationIntent.openApp(context)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentIntent(openAppPending)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)

        when {
            isHubActive && isSyncActive -> {
                builder.setSubText("Techuboard • Active")
                    .setContentTitle("⚡ LAN Sync & Floating Hub")
                    .setContentText("Syncing clips with Mac • Floating hub ready")
                    .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)

                val stopHubIntent = Intent(context, FloatingHubService::class.java).apply {
                    action = FloatingHubService.ACTION_STOP_SERVICE
                }
                val stopHubPending = PendingIntent.getService(
                    context,
                    1,
                    stopHubIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Turn Off Hub", stopHubPending)
                builder.addAction(android.R.drawable.ic_menu_view, "Open App", openAppPending)
            }
            isHubActive -> {
                builder.setSubText("Techuboard")
                    .setContentTitle("🎯 Floating Hub Active")
                    .setContentText("Tap floating pill to paste clips anywhere")
                    .setSmallIcon(android.R.drawable.ic_menu_edit)

                val stopHubIntent = Intent(context, FloatingHubService::class.java).apply {
                    action = FloatingHubService.ACTION_STOP_SERVICE
                }
                val stopHubPending = PendingIntent.getService(
                    context,
                    1,
                    stopHubIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Turn Off Hub", stopHubPending)
                builder.addAction(android.R.drawable.ic_menu_view, "Open App", openAppPending)
            }
            else -> {
                builder.setSubText("Techuboard")
                    .setContentTitle("🔄 LAN Sync Active")
                    .setContentText("Keeping clipboard sync alive")
                    .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)

                val startHubIntent = Intent(context, FloatingHubService::class.java)
                val startHubPending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    PendingIntent.getForegroundService(
                        context,
                        2,
                        startHubIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                } else {
                    PendingIntent.getService(
                        context,
                        2,
                        startHubIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                }
                builder.addAction(android.R.drawable.ic_menu_add, "Start Hub", startHubPending)
                builder.addAction(android.R.drawable.ic_menu_view, "Open App", openAppPending)
            }
        }

        return builder.build()
    }

    fun update(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.notify(NOTIFICATION_ID, buildUnifiedNotification(context))
        } catch (_: Exception) {}
    }
}
