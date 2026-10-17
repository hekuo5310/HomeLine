package net.zerexa.homeline

import android.content.Context
import android.os.Build
import android.telecom.*

class HomeConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(account: PhoneAccountHandle?, request: ConnectionRequest): Connection =
        TelecomBridge.create(this, request, true)
    override fun onCreateOutgoingConnection(account: PhoneAccountHandle?, request: ConnectionRequest): Connection =
        TelecomBridge.create(this, request, false)
    override fun onCreateIncomingConnectionFailed(account: PhoneAccountHandle?, request: ConnectionRequest) {
        request.extras?.getString("id")?.let { TelecomBridge.emit?.invoke(mapOf("id" to it, "action" to "reject")); TelecomBridge.end(it) }
    }
    override fun onCreateOutgoingConnectionFailed(account: PhoneAccountHandle?, request: ConnectionRequest) {
        request.extras?.getString("id")?.let { TelecomBridge.emit?.invoke(mapOf("id" to it, "action" to "disconnect")); TelecomBridge.end(it) }
    }
}

class HomeConnection(private val context: Context, val callId: String) : Connection() {
    var endpoints: List<CallEndpoint> = emptyList()
    private fun emit(action: String) {
        TelecomBridge.emit?.invoke(mapOf("id" to callId, "action" to action)) ?: finish()
    }
    override fun onAnswer() = emit("answer")
    override fun onAnswer(videoState: Int) = emit("answer")
    override fun onReject() = emit("reject")
    override fun onDisconnect() = emit("disconnect")
    override fun onAbort() = emit("disconnect")
    override fun onShowIncomingCallUi() {
        TelecomBridge.notify(context, callId, callerDisplayName?.toString() ?: "未知号码", state == STATE_ACTIVE)
    }
    override fun onAvailableCallEndpointsChanged(availableEndpoints: MutableList<CallEndpoint>) {
        if (Build.VERSION.SDK_INT >= 34) endpoints = availableEndpoints.toList()
    }
    override fun onCallEndpointChanged(endpoint: CallEndpoint) {
        if (Build.VERSION.SDK_INT >= 34) TelecomBridge.emit?.invoke(mapOf("id" to callId,
            "action" to "audio", "route" to endpoint.endpointName.toString()))
    }
    @Suppress("DEPRECATION")
    override fun onCallAudioStateChanged(state: CallAudioState) {
        TelecomBridge.emit?.invoke(mapOf("id" to callId, "action" to "audio", "route" to CallAudioState.audioRouteToString(state.route)))
    }
    fun notifyOngoing() = TelecomBridge.notify(context, callId, callerDisplayName?.toString() ?: "HomeLine", true)
    fun finish() {
        context.getSystemService(android.app.NotificationManager::class.java).cancel(callId, 1)
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
    }
}
