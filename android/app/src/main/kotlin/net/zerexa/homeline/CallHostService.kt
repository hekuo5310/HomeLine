package net.zerexa.homeline

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*

/** Short recovery lease, extended only by a real Telecom call. No boot restart. */
class CallHostService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var recoveryDeadline = 0L
    private var wakeLock: PowerManager.WakeLock? = null
    private val tick = object : Runnable {
        override fun run() {
            HostBridge.flush()
            if (!TelecomBridge.hasCalls() && WakeStore(this@CallHostService).all().isEmpty() && System.currentTimeMillis() >= recoveryDeadline) {
                stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return
            }
            handler.postDelayed(this, 1000)
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("call_host", "HomeLine 通话连接", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, "call_host").setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle("HomeLine").setContentText("正在维护电话连接").setOngoing(true).setContentIntent(open).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(92, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
        else startForeground(92, notification)
        if (wakeLock == null) {
            wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HomeLine:call-recovery")
            wakeLock?.acquire(120_000)
        }
        recoveryDeadline = System.currentTimeMillis() + 30_000
        CallEngine.get(this)
        handler.removeCallbacks(tick); handler.postDelayed(tick, 1000)
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = null
    companion object {
        fun stopIfIdle(context: Context) { if (!TelecomBridge.hasCalls() && WakeStore(context).all().isEmpty()) context.stopService(Intent(context, CallHostService::class.java)) }
        fun start(context: Context) { context.startForegroundService(Intent(context, CallHostService::class.java)) }
    }
}
