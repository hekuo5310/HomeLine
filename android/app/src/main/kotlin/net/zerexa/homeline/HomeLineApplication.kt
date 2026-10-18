package net.zerexa.homeline

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** One engine owns the SIP transport whether or not an Activity is attached. */
class HomeLineApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Do not start a calling service from Application/BOOT_COMPLETED.
        // Engine startup is demand-driven by the Activity or an eligible FCM wake.
    }
}

object CallEngine {
    private var engine: FlutterEngine? = null
    @Synchronized fun get(context: Context): FlutterEngine {
        engine?.let { return it }
        val created = FlutterEngine(context.applicationContext)
        created.plugins.add(HomeLinePlugin())
        engine = created
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return created
    }
}
