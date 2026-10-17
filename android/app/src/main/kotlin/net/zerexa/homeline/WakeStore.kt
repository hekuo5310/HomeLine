package net.zerexa.homeline

import android.content.Context
import org.json.JSONObject
import java.time.Instant

/** Only bounded, expiring call identifiers are persisted, never credentials. */
class WakeStore(context: Context) {
    companion object { private val lock = Any() }
    private val prefs = context.getSharedPreferences("call_wakes", Context.MODE_PRIVATE)
    fun add(data: Map<String, String>, now: Long = System.currentTimeMillis()): Boolean = synchronized(lock) {
        if (data["type"] != "incoming_call") return@synchronized false
        val id = data["call_id"] ?: return@synchronized false
        val expiry = try { Instant.parse(data["expires_at"]).toEpochMilli() } catch (_: Exception) { return@synchronized false }
        if (id.isEmpty() || id.length > 200 || expiry <= now || expiry > now + 120_000) return@synchronized false
        prune(now)
        if (prefs.contains(id) || prefs.all.size >= 64) return@synchronized false
        val json = JSONObject(mapOf("type" to "incoming_call", "call_id" to id, "expires_at" to data["expires_at"]!!))
            .put("received_at", Instant.ofEpochMilli(now).toString())
        prefs.edit().putString(id, json.toString()).commit()
    }
    fun all(now: Long = System.currentTimeMillis()): List<Map<String, Any>> = synchronized(lock) {
        prune(now)
        prefs.all.values.mapNotNull { raw ->
            try {
                val json = JSONObject(raw as String)
                json.keys().asSequence().associateWith { json.getString(it) }
            } catch (_: Exception) { null }
        }
    }
    fun remove(id: String) { synchronized(lock) { prefs.edit().remove(id).commit() } }
    fun clear() { synchronized(lock) { prefs.edit().clear().commit() } }
    private fun prune(now: Long) {
        val edit = prefs.edit()
        for ((key, raw) in prefs.all) {
            try {
                if (Instant.parse(JSONObject(raw as String).getString("expires_at")).toEpochMilli() <= now) edit.remove(key)
            } catch (_: Exception) { edit.remove(key) }
        }
        edit.commit()
    }
}
