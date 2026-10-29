package dev.tuist.app.data.network

import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.auth.AuthEventBus
import dev.tuist.app.data.auth.TokenStorage
import io.mockk.every
import io.mockk.mockk
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TokenRefreshAuthenticatorTest {
    @Test
    fun `concurrent unauthorized requests reuse the refreshed session`() {
        MockWebServer().use { server ->
            val release = CountDownLatch(1)
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    check(release.await(5, TimeUnit.SECONDS))
                    return MockResponse().setBody("""{"access_token":"new-access","refresh_token":"new-refresh"}""")
                }
            }
            server.start()
            val credentials = AtomicReference("old-access" to "old-refresh")
            val storage = mockk<TokenStorage> {
                every { getAccessToken() } answers { credentials.get().first }
                every { getRefreshToken() } answers { credentials.get().second }
                every { storeTokens(any(), any()) } answers {
                    credentials.set(firstArg<String>() to secondArg<String>())
                }
            }
            val environment = mockk<EnvironmentConfig> {
                every { serverUrl } returns server.url("/").toString()
            }
            val client = OkHttpClient()
            val authenticator = TokenRefreshAuthenticator(storage, client, environment, AuthEventBus())
            val request = Request.Builder()
                .url(server.url("/api/projects"))
                .header("Authorization", "Bearer old-access")
                .build()
            val response = Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(401)
                .message("Unauthorized")
                .build()
            val executor = Executors.newFixedThreadPool(2)
            val second = FutureTask<Request?> { authenticator.authenticate(null, response) }
            val secondThread = Thread(second)
            try {
                val first = executor.submit<Request?> { authenticator.authenticate(null, response) }
                checkNotNull(server.takeRequest(5, TimeUnit.SECONDS))
                secondThread.start()
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                fun waiting() = secondThread.state == Thread.State.BLOCKED &&
                    secondThread.stackTrace.firstOrNull()?.methodName == "authenticate"
                while (!waiting() && server.requestCount < 2 && !second.isDone && System.nanoTime() < deadline) Thread.yield()
                check(waiting() || server.requestCount == 2 || second.isDone) { "Second request never reached the authenticator" }
                release.countDown()
                assertEquals("Bearer new-access", first.get(5, TimeUnit.SECONDS)?.header("Authorization"))
                assertEquals("Bearer new-access", second.get(5, TimeUnit.SECONDS)?.header("Authorization"))
                assertEquals("new-access" to "new-refresh", credentials.get())
                assertEquals(1, server.requestCount)
            } finally {
                release.countDown()
                secondThread.interrupt()
                secondThread.join(5000)
                executor.shutdownNow()
                client.connectionPool.evictAll()
                client.dispatcher.executorService.shutdown()
            }
        }
    }
}
