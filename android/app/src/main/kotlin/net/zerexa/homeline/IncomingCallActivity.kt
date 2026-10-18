package net.zerexa.homeline

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Native lockscreen UI; never sets a call active from a button press. */
class IncomingCallActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val checkCall = object : Runnable {
        override fun run() {
            val id = intent.getStringExtra("id")
            if (!TelecomBridge.connections.containsKey(id)) finish()
            else handler.postDelayed(this, 500)
        }
    }
    override fun onResume() { super.onResume(); HostBridge.visible = true }
    override fun onPause() { HostBridge.visible = false; super.onPause() }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        val id = intent.getStringExtra("id") ?: run { finish(); return }
        val connection = TelecomBridge.connections[id] ?: run { finish(); return }
        val ringing = connection.state == android.telecom.Connection.STATE_RINGING
        val action = intent.getStringExtra("action")
        if (action != null && action != "open") {
            TelecomBridge.emit?.invoke(mapOf("id" to id, "action" to action))
            finish(); return
        }
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(32, 64, 32, 64)
            setBackgroundColor(android.graphics.Color.WHITE)
        }
        layout.addView(TextView(this).apply { text = "HomeLine ${if (ringing) "来电" else "通话中"}\n${TelecomBridge.displayName(this@IncomingCallActivity, connection.callerDisplayName?.toString() ?: "HomeLine")}"; textSize = 28f; gravity = Gravity.CENTER; setTextColor(android.graphics.Color.BLACK) })
        for ((label, event) in (if (ringing) listOf("接听" to "answer", "拒接" to "reject") else listOf("挂断" to "disconnect"))) {
            layout.addView(Button(this).apply { text = label; setOnClickListener {
                isEnabled = false
                TelecomBridge.emit?.invoke(mapOf("id" to id, "action" to event))
                finish()
            } })
        }
        setContentView(layout)
        handler.post(checkCall)
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); super.onDestroy() }
}
