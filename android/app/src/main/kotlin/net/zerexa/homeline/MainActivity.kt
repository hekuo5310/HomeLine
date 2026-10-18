package net.zerexa.homeline

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onResume() { super.onResume(); HostBridge.visible = true }
    override fun onPause() { HostBridge.visible = false; super.onPause() }
    override fun provideFlutterEngine(context: Context): FlutterEngine = CallEngine.get(context)
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Generated plugins and HomeLinePlugin were installed by CallEngine.
    }
}
