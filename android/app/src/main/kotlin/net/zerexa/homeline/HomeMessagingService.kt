package net.zerexa.homeline

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** Data-only FCM messages. Never synthesize a ringing or connected SIP dialog. */
class HomeMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val store = WakeStore(this)
        val added = store.add(message.data)
        if (!added && store.all().none { it["call_id"] == message.data["call_id"] }) return
        // A duplicate may retry a previously OS-rejected start. The durable hint
        // and Dart recovery remain deduplicated; its original expiry is unchanged.
        if (message.priority != RemoteMessage.PRIORITY_HIGH) {
            // Keep the hint for a later visible launch; background FGS is forbidden.
            return
        }
        try { CallHostService.start(this) }
        catch (_: RuntimeException) {
            // OS restrictions/downgraded push: the PBX must use timeout/fallback.
            // Never bypass the OS by launching an Activity from the background.
        }
    }
    override fun onNewToken(token: String) { HostBridge.notifyTokenChanged() }
    override fun onDeletedMessages() { HostBridge.invalidate() }
}
