package dev.tuist.gradle

import dev.tuist.gradle.api.model.CacheToken
import dev.tuist.gradle.services.CacheFreeTierExhaustedException
import dev.tuist.gradle.services.GetCacheTokenService
import org.junit.jupiter.api.Test
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertSame

class CacheTokenStoreTest {

    private val serverURL = URI("https://tuist.example")
    private val tokenProvider = TokenProvider(serverURL, envProvider = { if (it == "TUIST_TOKEN") "credential" else null })
    private val clock = AtomicLong(System.currentTimeMillis())

    private class FakeService(var respond: (Int) -> CacheToken) : GetCacheTokenService(retrofitProvider = { _, _ -> error("unused") }) {
        val calls = AtomicInteger(0)
        val fullHandles = mutableListOf<String>()

        override fun getCacheToken(serverURL: URI, fullHandle: String, tokenProvider: TokenProvider): CacheToken {
            synchronized(fullHandles) { fullHandles += fullHandle }
            return respond(calls.incrementAndGet())
        }
    }

    private fun store(service: FakeService) = CacheTokenStore(
        serverURL = serverURL,
        fullHandle = "account/project",
        tokenProvider = tokenProvider,
        getCacheTokenService = service,
        now = clock::get
    )

    @Test
    fun `reuses the exchanged token until it nears expiry`() {
        val service = FakeService { CacheToken(expiresIn = 1800, token = "cache-token-$it") }
        val store = store(service)

        val first = store.resolve()
        val second = store.resolve()

        assertEquals(CacheTokenStore.Exchanged("cache-token-1", clock.get() + 1_740_000), first)
        assertEquals(first, second)
        assertEquals(1, service.calls.get())
        assertEquals(listOf("account/project"), service.fullHandles)
    }

    @Test
    fun `collapses concurrent callers onto one exchange`() {
        val release = CountDownLatch(1)
        val service = FakeService {
            release.await(5, TimeUnit.SECONDS)
            CacheToken(expiresIn = 1800, token = "cache-token-$it")
        }
        val store = store(service)
        val executor = Executors.newFixedThreadPool(8)

        try {
            val results = (1..8).map { executor.submit<CacheTokenStore.Resolution> { store.resolve() } }
            Thread.sleep(100)
            release.countDown()

            assertEquals(setOf("cache-token-1"), results.map { (it.get() as CacheTokenStore.Exchanged).token }.toSet())
            assertEquals(1, service.calls.get())
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `exchanges again once the token is within the expiry margin`() {
        val service = FakeService { CacheToken(expiresIn = 60, token = "cache-token-$it") }
        val store = store(service)

        assertEquals("cache-token-1", (store.resolve() as CacheTokenStore.Exchanged).token)
        assertEquals("cache-token-2", (store.resolve() as CacheTokenStore.Exchanged).token)
    }

    @Test
    fun `exchanges again when forced`() {
        val service = FakeService { CacheToken(expiresIn = 1800, token = "cache-token-$it") }
        val store = store(service)

        store.resolve()

        assertEquals("cache-token-2", (store.resolve(forceRefresh = true) as CacheTokenStore.Exchanged).token)
    }

    @Test
    fun `falls back to the credential when the exchange fails and retries after a minute`() {
        val service = FakeService { throw RuntimeException("Not Found") }
        val store = store(service)

        assertEquals(CacheTokenStore.Unavailable(clock.get() + 60_000), store.resolve())
        assertEquals(CacheTokenStore.Unavailable(clock.get() + 60_000), store.resolve())
        assertEquals(1, service.calls.get())

        clock.addAndGet(60_000)
        service.respond = { CacheToken(expiresIn = 1800, token = "cache-token-$it") }

        assertEquals("cache-token-2", (store.resolve() as CacheTokenStore.Exchanged).token)
    }

    @Test
    fun `does not fall back to the credential when the free tier is exhausted`() {
        val service = FakeService { throw CacheFreeTierExhaustedException("Upgrade your plan.") }
        val store = store(service)

        val first = assertFailsWith<CacheFreeTierExhaustedException> { store.resolve() }
        clock.addAndGet(3_600_000)
        val second = assertFailsWith<CacheFreeTierExhaustedException> { store.resolve(forceRefresh = true) }

        assertEquals("Upgrade your plan.", first.message)
        assertSame(first, second)
        assertEquals(1, service.calls.get())
    }
}
