package net.zerexa.homeline

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object HostBridge {
    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var ready = false
    var visible = false
    private var startupJournal: Set<String> = emptySet()
    fun attach(context: Context, messenger: BinaryMessenger) {
        this.context = context
        startupJournal = context.getSharedPreferences("call_journal", Context.MODE_PRIVATE).getStringSet("active", emptySet())!!.toSet()
        channel = MethodChannel(messenger, "net.zerexa.homeline/host")
        channel!!.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "privacy" -> {
                        val hidden = call.argument<Boolean>("hide_caller")
                        val prefs = context.getSharedPreferences("privacy", Context.MODE_PRIVATE)
                        if (hidden != null) prefs.edit().putBoolean("hide_caller", hidden).commit()
                        result.success(prefs.getBoolean("hide_caller", true))
                    }
                    "journalActive" -> {
                        val id = requireNotNull(call.argument<String>("call_id"))
                        val prefs = context.getSharedPreferences("call_journal", Context.MODE_PRIVATE)
                        val ids = prefs.getStringSet("active", emptySet())!!.toMutableSet(); ids.add(id)
                        prefs.edit().putStringSet("active", ids).commit(); result.success(null)
                    }
                    "journalEnd" -> {
                        val id = requireNotNull(call.argument<String>("call_id"))
                        val prefs = context.getSharedPreferences("call_journal", Context.MODE_PRIVATE)
                        val ids = prefs.getStringSet("active", emptySet())!!.toMutableSet(); ids.remove(id)
                        prefs.edit().putStringSet("active", ids).commit(); startupJournal = startupJournal - id; result.success(null)
                    }
                    "ready" -> { ready = true; result.success(null); flush() }
                    "completeWake" -> { WakeStore(context).remove(requireNotNull(call.argument<String>("call_id"))); CallHostService.stopIfIdle(context); result.success(null) }
                    "clear" -> { WakeStore(context).clear(); context.getSharedPreferences("call_journal", Context.MODE_PRIVATE).edit().clear().commit(); startupJournal = emptySet(); CallHostService.stopIfIdle(context); result.success(null) }
                    "releaseFocus" -> { HomeConnectionService.releaseFocus?.invoke(); result.success(null) }
                    "keepAlive" -> { CallHostService.start(context); result.success(null) }
                    "token" -> {
                        check(FirebaseApp.initializeApp(context) != null) { "Firebase configuration missing" }
                        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if (task.isSuccessful) result.success(task.result) else result.error("FCM_UNAVAILABLE", "Push registration failed", null)
                        }
                    }
                    "status" -> result.success(mapOf("notifications" to context.getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled(),
                        "full_screen" to (android.os.Build.VERSION.SDK_INT < 34 || context.getSystemService(android.app.NotificationManager::class.java).canUseFullScreenIntent()),
                        "calls" to TelecomBridge.hasCalls(), "visible" to visible))
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("HOST_UNAVAILABLE", "Calling host unavailable", null) }
        }
    }
    fun flush() {
        val c = context ?: return
        if (!ready) return
        for (id in startupJournal) channel?.invokeMethod("interrupted", mapOf("call_id" to id))
        for (hint in WakeStore(c).all()) channel?.invokeMethod("wake", hint)
    }
    fun notifyTokenChanged() { Handler(Looper.getMainLooper()).post { if (ready) channel?.invokeMethod("tokenChanged", null) } }
    fun invalidate() { Handler(Looper.getMainLooper()).post { if (ready) channel?.invokeMethod("invalidate", null) } }
    fun detach() { ready = false; channel?.setMethodCallHandler(null); channel = null; context = null }
}
