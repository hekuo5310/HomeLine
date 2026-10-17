package net.zerexa.homeline

import android.content.Intent
import android.os.Build
import android.telecom.CallAudioState
import android.telecom.CallEndpoint
import android.os.OutcomeReceiver
import android.telecom.CallEndpointException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "net.zerexa.homeline/telecom")
        TelecomBridge.emit = { event -> runOnUiThread { channel?.invokeMethod("action", event) } }
        channel!!.setMethodCallHandler { call, result ->
            try {
                val id = call.argument<String>("id")
                when (call.method) {
                    "configure" -> {
                        TelecomBridge.register(this)
                        if (Build.VERSION.SDK_INT >= 34 && !getSystemService(android.app.NotificationManager::class.java).canUseFullScreenIntent()) {
                            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                android.net.Uri.parse("package:$packageName")))
                        }
                        result.success(null)
                    }
                    "show" -> {
                        TelecomBridge.show(this, requireNotNull(id), call.argument<String>("remote") ?: "未知号码", call.argument<Boolean>("incoming") == true)
                        result.success(null)
                    }
                    "active" -> { TelecomBridge.activate(requireNotNull(id)); result.success(null) }
                    "end" -> { TelecomBridge.end(requireNotNull(id)); result.success(null) }
                    "route" -> {
                        val connection = TelecomBridge.connections[id] ?: error("Call no longer exists")
                        val name = call.argument<String>("route")
                        if (Build.VERSION.SDK_INT >= 34) {
                            val type = when (name) {
                                "speaker" -> CallEndpoint.TYPE_SPEAKER
                                "bluetooth" -> CallEndpoint.TYPE_BLUETOOTH
                                else -> CallEndpoint.TYPE_EARPIECE
                            }
                            val endpoint = connection.endpoints.firstOrNull { it.endpointType == type }
                                ?: error("Requested audio endpoint is unavailable")
                            connection.requestCallEndpointChange(endpoint, mainExecutor,
                                object : OutcomeReceiver<Void, CallEndpointException> {
                                    override fun onResult(value: Void?) { result.success(null) }
                                    override fun onError(error: CallEndpointException) { result.error("ROUTE_FAILED", "Audio route change failed", null) }
                                })
                        } else {
                            val route = when (name) {
                                "speaker" -> CallAudioState.ROUTE_SPEAKER
                                "bluetooth" -> CallAudioState.ROUTE_BLUETOOTH
                                else -> CallAudioState.ROUTE_EARPIECE
                            }
                            @Suppress("DEPRECATION")
                            connection.setAudioRoute(route)
                            result.success(null) // Confirmation comes from onCallAudioStateChanged.
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("TELECOM_UNAVAILABLE", "Enable HomeLine calling account and check permissions", null)
            }
        }
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        TelecomBridge.emit = null
        channel?.setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
