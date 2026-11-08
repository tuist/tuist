package dev.tuist.app.data.jams

import com.squareup.moshi.Moshi
import dev.tuist.app.data.auth.TokenStorage
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import java.io.IOException
import java.util.Base64
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import okhttp3.Authenticator
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.logging.HttpLoggingInterceptor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.Retrofit

@OptIn(ExperimentalCoroutinesApi::class)
class JamWatcherTest {
    private val moshi = Moshi.Builder().build()
    private val frames = moshi.adapter(List::class.java)
    private val auth = Interceptor { error("Tests must not access the network") }
    private val logger = HttpLoggingInterceptor().setLevel(HttpLoggingInterceptor.Level.BODY)
    private val original =
        OkHttpClient.Builder()
            .addInterceptor(auth)
            .addInterceptor(logger)
            .addNetworkInterceptor(logger)
            .build()
    private val retrofit =
        Retrofit.Builder().baseUrl("https://selected.example/prefix/").client(original).build()
    private val attempts = mutableListOf<Attempt>()
    private val authorized = mutableListOf<String>()
    private var credential: String? = "private+/=token"
    private var invalidations = 0
    private var disconnections = 0
    private var authorize: suspend (String) -> String = { authorized.add(it); "jams" }
    private val watcher =
        JamWatcher(retrofit, moshi, { authorize(it) }, { credential }) {
            client,
            request,
            listener ->
            val socket = mockk<WebSocket>(relaxed = true)
            val sent = mutableListOf<List<*>>()
            every { socket.send(any<String>()) } answers
                {
                    sent.add(frames.fromJson(firstArg<String>())!!)
                    true
                }
            attempts.add(Attempt(client, request, listener, socket, sent))
            socket
        }

    @Test
    fun `handshake preserves selected TLS origin and auth without logging or token URL`() =
        runTest {
            val job = launch { watch() }
            runCurrent()
            val attempt = attempts.single()
            assertEquals(listOf("acme"), authorized)
            assertEquals(
                "https://selected.example/prefix/jams/socket/websocket?vsn=2.0.0",
                attempt.request.url.toString(),
            )
            assertEquals(setOf("vsn"), attempt.request.url.queryParameterNames)
            val encoded =
                Base64.getUrlEncoder().withoutPadding().encodeToString(credential!!.toByteArray())
            assertEquals(
                "phoenix, base64url.bearer.phx.$encoded",
                attempt.request.header("Sec-WebSocket-Protocol"),
            )
            assertFalse(attempt.request.url.toString().contains(credential!!))
            assertEquals(listOf(auth), attempt.client.interceptors)
            assertTrue(attempt.client.networkInterceptors.isEmpty())
            assertSame(original.sslSocketFactory, attempt.client.sslSocketFactory)
            assertSame(original.hostnameVerifier, attempt.client.hostnameVerifier)
            assertSame(Authenticator.NONE, attempt.client.authenticator)
            assertTrue(original.interceptors.contains(logger))
            assertTrue(original.networkInterceptors.contains(logger))
            attempt.open()
            runCurrent()
            assertEquals(
                listOf("1", "1", "jams:acme:inbox", "phx_join", emptyMap<String, Any>()),
                attempt.sent.single(),
            )
            job.cancelAndJoin()
        }

    @Test
    fun `join and snapshots invalidate only matching topic and join references`() = runTest {
        val job = launch { watch("jam-id") }
        runCurrent()
        val attempt = attempts.single()
        attempt.open()
        runCurrent()
        assertEquals("jams:acme:jam-id", attempt.sent.single()[2])
        attempt.message("snapshot", topic = "jams:acme:jam-id")
        attempt.message("phx_reply", ref = "wrong", topic = "jams:acme:jam-id")
        attempt.message("phx_reply", topic = "jams:other:jam-id")
        attempt.message("phx_reply", join = "stale", topic = "jams:acme:jam-id")
        runCurrent()
        assertEquals(0, invalidations)
        attempt.message("phx_reply", topic = "jams:acme:jam-id")
        runCurrent()
        assertEquals(1, invalidations)
        attempt.message("snapshot", join = null, ref = null, topic = "jams:acme:jam-id")
        attempt.message("snapshot", join = "stale", topic = "jams:acme:jam-id")
        attempt.message("snapshot", topic = "jams:other:inbox")
        attempt.listener.onMessage(attempt.socket, "not json")
        runCurrent()
        assertEquals(2, invalidations)
        assertEquals(0, disconnections)
        job.cancelAndJoin()
    }

    @Test
    fun `heartbeat requires matching phoenix acknowledgement and detects silent disconnect`() =
        runTest {
            val job = launch { watch() }
            runCurrent()
            val attempt = attempts.single()
            attempt.open()
            attempt.message("phx_reply")
            runCurrent()
            advanceTimeBy(10_000)
            runCurrent()
            assertEquals(
                listOf(null, "2", "phoenix", "heartbeat", emptyMap<String, Any>()),
                attempt.sent.last(),
            )
            attempt.message("phx_reply", join = null, ref = "2", topic = "phoenix")
            runCurrent()
            advanceTimeBy(20_000)
            runCurrent()
            assertEquals("3", attempt.sent.last()[1])
            attempt.message("phx_reply", join = null, ref = "wrong", topic = "phoenix")
            attempt.message("phx_reply", join = null, ref = "3", topic = "jams:acme:inbox")
            runCurrent()
            advanceTimeBy(20_000)
            runCurrent()
            assertEquals(1, disconnections)
            verify(exactly = 1) { attempt.socket.cancel() }
            job.cancelAndJoin()
        }

    @Test
    fun `missing join acknowledgement times out and reconnects`() = runTest {
        val job = launch { watch() }
        runCurrent()
        attempts.single().open()
        runCurrent()
        advanceTimeBy(10_000)
        runCurrent()
        assertEquals(1, disconnections)
        advanceTimeBy(2_000)
        runCurrent()
        assertEquals(2, attempts.size)
        job.cancelAndJoin()
    }

    @Test
    fun `channel error and close reconnect reauthorize rotate credentials and refetch without writes`() =
        runTest {
            val job = launch { watch() }
            runCurrent()
            val first = attempts.single()
            first.open()
            first.message("phx_reply")
            first.message("phx_error", topic = "jams:other:inbox")
            runCurrent()
            assertEquals(1, invalidations)
            assertEquals(0, disconnections)
            first.message("phx_error")
            runCurrent()
            credential = "rotated-token"
            advanceTimeBy(1_999)
            runCurrent()
            assertEquals(1, attempts.size)
            advanceTimeBy(1)
            runCurrent()
            val second = attempts.last()
            second.open()
            second.message("phx_reply")
            runCurrent()
            assertEquals(2, invalidations)
            assertEquals(listOf("acme", "acme"), authorized)
            assertTrue(
                second.request
                    .header("Sec-WebSocket-Protocol")!!
                    .endsWith(
                        Base64.getUrlEncoder()
                            .withoutPadding()
                            .encodeToString("rotated-token".toByteArray())
                    )
            )
            assertEquals(listOf("phx_join"), second.sent.map { it[3] })
            second.message("phx_close")
            runCurrent()
            advanceTimeBy(4_000)
            runCurrent()
            assertEquals(3, attempts.size)
            job.cancelAndJoin()
        }

    @Test
    fun `network failures use bounded exponential backoff`() = runTest {
        val job = launch { watch() }
        runCurrent()
        for (wait in listOf(2_000L, 4_000L, 8_000L, 16_000L, 32_000L, 32_000L)) {
            val count = attempts.size
            val attempt = attempts.last()
            attempt.listener.onFailure(attempt.socket, IOException("offline"), null)
            runCurrent()
            advanceTimeBy(wait - 1)
            runCurrent()
            assertEquals(count, attempts.size)
            advanceTimeBy(1)
            runCurrent()
            assertEquals(count + 1, attempts.size)
        }
        job.cancelAndJoin()
    }

    @Test
    fun `cancellation closes socket heartbeat and reconnect loop`() = runTest {
        val job = launch { watch() }
        runCurrent()
        val attempt = attempts.single()
        attempt.open()
        attempt.message("phx_reply")
        runCurrent()
        job.cancelAndJoin()
        verify(exactly = 1) { attempt.socket.close(1000, null) }
        verify(exactly = 1) { attempt.socket.cancel() }
        advanceTimeBy(120_000)
        runCurrent()
        assertEquals(1, attempts.size)
        assertEquals(1, attempt.sent.size)
        assertEquals(0, disconnections)
    }

    @Test
    fun `authorization failure never opens socket and cancellation stops backoff`() = runTest {
        authorize = { throw IOException("offline") }
        val job = launch { watch() }
        runCurrent()
        assertTrue(attempts.isEmpty())
        assertEquals(1, disconnections)
        job.cancelAndJoin()
        advanceTimeBy(120_000)
        runCurrent()
        assertEquals(1, disconnections)
    }

    @Test
    fun `each attempt reads credentials after authorization refresh and never connects without them`() =
        runTest {
            credential = null
            val job = launch { watch() }
            runCurrent()
            assertTrue(attempts.isEmpty())
            assertEquals(1, disconnections)
            authorize = { credential = "fresh-from-http"; "jams" }
            advanceTimeBy(2_000)
            runCurrent()
            val expected =
                Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString("fresh-from-http".toByteArray())
            assertEquals(
                "phoenix, base64url.bearer.phx.$expected",
                attempts.single().request.header("Sec-WebSocket-Protocol"),
            )
            attempts.single().open()
            attempts.single().message("phx_reply", status = "error")
            runCurrent()
            assertEquals(0, invalidations)
            assertEquals(2, disconnections)
            job.cancelAndJoin()
        }

    @Test
    fun `injected constructor authorizes HTTP before reading current storage token`() = runTest {
        val storage = mockk<TokenStorage>()
        every { storage.snapshot() } returns TokenStorage.Session("profile", 0)
        val transport = mockk<JamTransport>()
        coEvery { transport.dialect("acme") } throws IOException("offline")
        val injected = JamWatcher(retrofit, moshi, storage, transport)
        val job = launch { injected.watch("acme", null, {}, {}) }
        runCurrent()
        coVerify(exactly = 1) { transport.dialect("acme") }
        verify(exactly = 0) { storage.getAccessToken() }
        job.cancelAndJoin()
    }

    @Test
    fun `legacy negotiation selects matching socket path and topic`() = runTest {
        authorize = { "threads" }
        val job = launch { watch("jam-id") }
        runCurrent()
        val attempt = attempts.single()
        assertEquals("/prefix/threads/socket/websocket", attempt.request.url.encodedPath)
        attempt.open()
        runCurrent()
        assertEquals("threads:acme:jam-id", attempt.sent.single()[2])
        attempt.message("phx_reply", topic = "threads:acme:jam-id")
        runCurrent()
        assertEquals(1, invalidations)
        job.cancelAndJoin()
    }

    private suspend fun watch(jamId: String? = null) =
        watcher.watch("acme", jamId, { invalidations++ }, { disconnections++ })

    private inner class Attempt(
        val client: OkHttpClient,
        val request: Request,
        val listener: WebSocketListener,
        val socket: WebSocket,
        val sent: MutableList<List<*>>,
    ) {
        fun open() =
            listener.onOpen(
                socket,
                Response.Builder()
                    .request(request)
                    .protocol(Protocol.HTTP_1_1)
                    .code(101)
                    .message("Switching Protocols")
                    .build(),
            )

        fun message(
            event: String,
            join: String? = "1",
            ref: String? = "1",
            topic: String = "jams:acme:inbox",
            status: String = "ok",
        ) =
            listener.onMessage(
                socket,
                frames.toJson(listOf(join, ref, topic, event, mapOf("status" to status))),
            )
    }
}
