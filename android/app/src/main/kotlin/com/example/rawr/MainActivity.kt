package com.example.rawr

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "edupocket/notifications"
    private val notificationChannelId = "edupocket_transactions"
    private val notificationPermissionRequest = 4201
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createTransactionNotificationChannel()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    requestNotificationPermission(result)
                }
                "showTransactionNotification" -> {
                    val rawNotificationId =
                        call.argument<Number>("notificationId")?.toLong() ?: 0L
                    val notificationId =
                        (rawNotificationId xor (rawNotificationId ushr 32)).toInt()
                    val transactionId = call.argument<Number>("transactionId")?.toLong() ?: 0L
                    val title = call.argument<String>("title") ?: "EduPocket"
                    val body = call.argument<String>("body") ?: "Transaction completed."
                    val shown = showTransactionNotification(
                        notificationId,
                        transactionId,
                        title,
                        body,
                    )
                    result.success(shown)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createTransactionNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            notificationChannelId,
            "Transaction updates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Notifications for EduPocket payments and wallet top-ups"
        }
        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPermissionResult != null) {
                result.success(false)
                return
            }
            pendingPermissionResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequest,
            )
            return
        }
        result.success(true)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequest) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun showTransactionNotification(
        notificationId: Int,
        transactionId: Long,
        title: String,
        body: String,
    ): Boolean {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!notificationDeliveryAllowed(manager)) return false

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("transaction_id", transactionId)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        return try {
            manager.notify(notificationId, notification)
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun notificationDeliveryAllowed(manager: NotificationManager): Boolean {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            !manager.areNotificationsEnabled()
        ) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = manager.getNotificationChannel(notificationChannelId)
            if (channel == null || channel.importance == NotificationManager.IMPORTANCE_NONE) {
                return false
            }
        }
        return true
    }
}
