package net.zerexa.homeline

import android.app.Application
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class WakeStoreTest {
    private lateinit var store: WakeStore
    private val now = Instant.parse("2026-10-18T00:00:00Z").toEpochMilli()
    private fun hint(id: String = "call", offset: Long = 30_000) = mapOf(
        "type" to "incoming_call", "call_id" to id, "expires_at" to Instant.ofEpochMilli(now + offset).toString())
    @Before fun reset() { store = WakeStore(RuntimeEnvironment.getApplication()); store.clear() }
    @Test fun rejectsExpiredAndUnboundedLifetime() {
        assertFalse(store.add(hint(offset = 0), now))
        assertFalse(store.add(hint(offset = 120_001), now))
        assertTrue(store.all(now).isEmpty())
    }
    @Test fun survivesStoreRecreationAndDeduplicates() {
        assertTrue(store.add(hint(), now))
        val recreated = WakeStore(RuntimeEnvironment.getApplication())
        assertFalse(recreated.add(hint(), now))
        assertEquals(1, recreated.all(now).size)
        assertTrue(recreated.all(now + 30_001).isEmpty())
    }
    @Test fun persistsOnlyAnAllowlistOfFields() {
        store.add(hint() + ("password" to "must-not-persist"), now)
        assertFalse(store.all(now).single().containsKey("password"))
    }
    @Test fun boundedUntrustedMessagesCannotGrowWithoutLimit() {
        repeat(64) { assertTrue(store.add(hint("call-$it"), now)) }
        assertFalse(store.add(hint("overflow"), now))
        store.remove("call-0")
        assertTrue(store.add(hint("replacement"), now))
    }
    @Test fun simultaneousReceiversAcrossStoreInstancesPersistOnce() {
        val context = RuntimeEnvironment.getApplication<Application>()
        val pool = java.util.concurrent.Executors.newFixedThreadPool(4)
        try {
            val gate = java.util.concurrent.CountDownLatch(1)
            val results = (1..8).map {
                pool.submit<Boolean> { gate.await(); WakeStore(context).add(hint(), now) }
            }
            gate.countDown()
            assertEquals(1, results.count { it.get(5, java.util.concurrent.TimeUnit.SECONDS) })
            assertEquals(1, store.all(now).size)
        } finally { pool.shutdownNow() }
    }

}
