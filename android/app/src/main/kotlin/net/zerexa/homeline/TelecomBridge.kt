package net.zerexa.homeline

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.*

/** Telecom state belongs to the process; persisted business IDs reconcile process loss. */
object TelecomBridge {
    val connections = mutableMapOf<String, HomeConnection>()
    private val pending = mutableSetOf<String>()
    private val ended = mutableSetOf<String>()
    private val active = mutableSetOf<String>()
    var emit: ((Map<String, Any>) -> Unit)? = null
    const val CHANNEL = "homeline_calls"
    fun hasCalls(): Boolean = pending.isNotEmpty() || connections.isNotEmpty()
    fun handle(context: Context) = PhoneAccountHandle(ComponentName(context, HomeConnectionService::class.java), "homeline")
    fun register(context: Context) {
        val telecom = context.getSystemService(TelecomManager::class.java)
        telecom.registerPhoneAccount(PhoneAccount.builder(handle(context), "HomeLine")
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
            .setSupportedUriSchemes(listOf(PhoneAccount.SCHEME_SIP)).build())
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(CHANNEL, "HomeLine 来电", NotificationManager.IMPORTANCE_HIGH)
        channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        channel.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build())
        manager.createNotificationChannel(channel)
    }
    fun show(context: Context, id: String, remote: String, incoming: Boolean) {
        if (id in ended || id in pending || connections.containsKey(id)) return
        check(emit != null) { "Foreground SIP engine unavailable" }
        register(context)
        CallHostService.start(context)
        val telecom = context.getSystemService(TelecomManager::class.java)
        val extras = Bundle().apply { putString("id", id); putString("remote", remote) }
        pending.add(id)
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (pending.remove(id)) {
                ended.add(id); active.remove(id)
                emit?.invoke(mapOf("action" to "disconnect", "id" to id))
                CallHostService.stopIfIdle(context)
            }
        }, 15_000)
        try {
            if (incoming) {
                extras.putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, Uri.fromParts("sip", remote, null))
                telecom.addNewIncomingCall(handle(context), extras)
            } else {
                telecom.placeCall(Uri.fromParts("sip", remote, null), Bundle().apply {
                    putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle(context))
                    putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, extras)
                })
            }
        } catch (e: Exception) { pending.remove(id); throw e }
    }
    fun create(context: Context, request: ConnectionRequest, incoming: Boolean): Connection {
        val requestExtras = request.extras ?: Bundle()
        val extras = requestExtras.getBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS) ?: requestExtras
        val id = extras.getString("id") ?: return Connection.createFailedConnection(DisconnectCause(DisconnectCause.ERROR))
        if (!pending.remove(id)) return Connection.createFailedConnection(DisconnectCause(DisconnectCause.CANCELED))
        if (id in ended || emit == null) return Connection.createFailedConnection(DisconnectCause(DisconnectCause.CANCELED))
        val c = HomeConnection(context.applicationContext, id)
        connections[id] = c
        c.connectionProperties = Connection.PROPERTY_SELF_MANAGED
        c.setAddress(request.address, TelecomManager.PRESENTATION_ALLOWED)
        c.setCallerDisplayName(extras.getString("remote") ?: "HomeLine", TelecomManager.PRESENTATION_ALLOWED)
        c.setAudioModeIsVoip(true)
        if (incoming) c.setRinging() else c.setDialing()
        // setActive must run after ConnectionService has returned the Connection.
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            if (id in active && id !in ended) { c.setActive(); c.notifyOngoing() }
        }
        return c
    }
    fun activate(id: String) {
        if (id in ended) return
        active.add(id)
        connections[id]?.let { c -> c.setActive(); c.notifyOngoing() }
    }
    fun end(id: String) {
        ended.add(id); pending.remove(id); active.remove(id)
        connections.remove(id)?.finish()
    }
    fun intent(context: Context, id: String, action: String): PendingIntent = PendingIntent.getActivity(context, 0,
        Intent(context, IncomingCallActivity::class.java).apply {
            data = Uri.Builder().scheme("homeline").authority("call").appendPath(id).appendPath(action).build()
            putExtra("id", id); putExtra("action", action)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun displayName(context: Context, remote: String): String {
        val hide = context.getSharedPreferences("privacy", Context.MODE_PRIVATE).getBoolean("hide_caller", true)
        return if (hide && context.getSystemService(android.app.KeyguardManager::class.java).isDeviceLocked) "HomeLine" else remote
    }
    fun notify(context: Context, id: String, remote: String, ongoing: Boolean) {
        val shownName = displayName(context, remote)
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.sym_call_incoming).setContentTitle(if (ongoing) "HomeLine 通话中" else "HomeLine 来电")
            .setContentText(shownName).setCategory(Notification.CATEGORY_CALL).setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setOnlyAlertOnce(ongoing)
            .setContentIntent(intent(context, id, "open"))
        if (Build.VERSION.SDK_INT >= 31) {
            val person = Person.Builder().setName(shownName.ifEmpty { "未知号码" }).setImportant(true).build()
            builder.setStyle(if (ongoing) Notification.CallStyle.forOngoingCall(person, intent(context, id, "disconnect"))
                else Notification.CallStyle.forIncomingCall(person, intent(context, id, "reject"), intent(context, id, "answer")))
        } else {
            builder.addAction(Notification.Action.Builder(null, "挂断", intent(context, id, if (ongoing) "disconnect" else "reject")).build())
            if (!ongoing) builder.addAction(Notification.Action.Builder(null, "接听", intent(context, id, "answer")).build())
        }
        if (!ongoing) builder.setFullScreenIntent(intent(context, id, "open"), true)
        context.getSystemService(NotificationManager::class.java).notify(id, 1, builder.build())
    }
}
