package dev.tuist.app.data.network

import android.content.Context
import android.content.SharedPreferences
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.auth.AuthEventBus
import dev.tuist.app.data.auth.TokenStorage
import io.mockk.every
import io.mockk.mockk
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
class ProfileRequestIsolationTest {
    @Test fun `stale successful response is discarded after switching profiles`() {
        scenario(refresh = false)
    }

    @Test fun `stale rotation does not overwrite the selected profile or retry with its token`() {
        scenario(refresh = true)
    }

    @Test fun `rotation released after A to B to A retains new pair without retrying stale request`() {
        scenario(refresh = true, switchBackBeforeResult = true)
    }

    @Test fun `failed rotation commit uses new pair on next request after A B`() {
        scenario(refresh = true, failRotationCommit = true)
    }

    @Test fun `failed rotation commit uses new pair on next request after A B A`() {
        scenario(refresh = true, switchBackBeforeResult = true, failRotationCommit = true)
    }

    @Test fun `stale rejection cannot expire the selected profile`() {
        scenario(refresh = true, rejected = true)
    }

    @Test fun `body arriving after headers cannot publish data from a previous profile`() {
        scenario(refresh = false, delayedBody = true)
    }

    @Test fun `rejection removes only the expired login and activates a remaining saved profile`() {
        scenario(refresh = true, rejected = true, switchBeforeResult = false)
    }

    @Test fun `failed automatic expiry reaches async failure and retains both logins durably for retry`() {
        scenario(refresh = true, rejected = true, switchBeforeResult = false, failExpiryCommit = true)
    }

    @Test fun `both conversation protocols stay scoped to the personal login despite legacy organization selection`() {
        val prefs = RuntimeEnvironment.getApplication().getSharedPreferences("conversation-isolation", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        val payload = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
            """{"email":"alice@example.invalid","preferred_username":"alice"}""".toByteArray(),
        )
        val server = MockWebServer()
        server.start()
        try {
            val tokens = TokenStorage(prefs, server.url("/").toString())
            tokens.storeTokens("header.$payload.signature", "alice-refresh")
            tokens.selectOrganization(tokens.snapshot().profileId!!, "legacy-org")
            val client = OkHttpClient.Builder().addInterceptor(AuthInterceptor(tokens)).build()
            for (collection in listOf("jams", "threads")) {
                repeat(2) { server.enqueue(MockResponse().setBody("personal history")) }
                client.newCall(Request.Builder().url(server.url("/api/accounts/alice/$collection")).build()).execute().use {
                    assertEquals("personal history", it.body!!.string())
                }
                assertEquals("/api/accounts/alice/$collection", server.takeRequest(5, TimeUnit.SECONDS)!!.path)
                assertThrows(IOException::class.java) {
                    client.newCall(Request.Builder().url(server.url("/api/accounts/legacy-org/$collection")).build()).execute().close()
                }
            }
            assertEquals(2, server.requestCount)
        } finally { server.shutdown() }
    }

    @Test fun `cross organization previews use current login while profile changes fence stale requests`() {
        val prefs = RuntimeEnvironment.getApplication().getSharedPreferences("organization-isolation", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        val server = MockWebServer()
        server.start()
        val executor = Executors.newSingleThreadExecutor()
        try {
            val tokens = TokenStorage(prefs, server.url("/").toString())
            tokens.storeTokens("alice-access", "alice-refresh")
            val id = tokens.snapshot().profileId!!
            tokens.selectOrganization(id, "alpha")
            val alpha = tokens.snapshot()
            val client = OkHttpClient.Builder().addInterceptor(AuthInterceptor(tokens))
                .addNetworkInterceptor(SessionGuardInterceptor(tokens)).build()
            server.enqueue(MockResponse().setBody("alpha-private-data").setHeadersDelay(500, TimeUnit.MILLISECONDS))
            val result = executor.submit<Boolean> {
                try {
                    client.newCall(Request.Builder().url(server.url("/api/projects/other/app/previews")).build()).execute().use { it.body?.string() }
                    false
                } catch (_: IOException) { true }
            }
            val outgoing = server.takeRequest(5, TimeUnit.SECONDS)!!
            assertEquals("/api/projects/other/app/previews", outgoing.path)
            assertEquals("Bearer alice-access", outgoing.getHeader("Authorization"))
            tokens.storeTokens("bob-access", "bob-refresh")
            assertTrue(result.get(5, TimeUnit.SECONDS))
            assertEquals("bob-refresh", tokens.getRefreshToken())
            val stale = Request.Builder().url(server.url("/api/projects/other/app/previews"))
                .tag(TokenStorage.Session::class.java, alpha).build()
            assertThrows(IOException::class.java) { client.newCall(stale).execute().close() }
            assertEquals(1, server.requestCount)
            server.enqueue(MockResponse().setBody("bob-project-data"))
            client.newCall(Request.Builder().url(server.url("/api/projects/other/app/previews")).build()).execute().use {
                assertEquals("bob-project-data", it.body!!.string())
            }
            assertEquals("Bearer bob-access", server.takeRequest(5, TimeUnit.SECONDS)!!.getHeader("Authorization"))
        } finally { executor.shutdownNow(); server.shutdown() }
    }

    private fun scenario(refresh: Boolean, rejected: Boolean = false, delayedBody: Boolean = false, switchBeforeResult: Boolean = true, switchBackBeforeResult: Boolean = false, failRotationCommit: Boolean = false, failExpiryCommit: Boolean = false) {
        val prefs = RuntimeEnvironment.getApplication().getSharedPreferences("isolation", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        val server = MockWebServer()
        server.start()
        var failNextCommit = false
        val faultPrefs = object : SharedPreferences by prefs {
            override fun edit(): SharedPreferences.Editor {
                val editor = prefs.edit()
                return object : SharedPreferences.Editor by editor {
                    override fun putString(key: String?, value: String?): SharedPreferences.Editor { editor.putString(key, value); return this }
                    override fun remove(key: String?): SharedPreferences.Editor { editor.remove(key); return this }
                    override fun commit(): Boolean {
                        val result = editor.commit()
                        if (!failNextCommit) return result
                        failNextCommit = false
                        return false
                    }
                }
            }
        }
        val tokens = TokenStorage(faultPrefs, server.url("/").toString())
        tokens.storeTokens("bob-access", "bob-refresh")
        val bob = tokens.snapshot().profileId!!
        tokens.storeTokens("alice-access", "alice-refresh")
        val alice = tokens.snapshot()
        val environment = mockk<EnvironmentConfig> {
            every { serverUrl } returns server.url("/").toString().trimEnd('/')
            every { oauthClientId } returns "android-client"
        }
        val headersObserved = java.util.concurrent.CountDownLatch(1)
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            chain.proceed(chain.request()).also { headersObserved.countDown() }
        }.addInterceptor(AuthInterceptor(tokens))
            .addNetworkInterceptor(SessionGuardInterceptor(tokens))
            .authenticator(TokenRefreshAuthenticator(tokens, OkHttpClient(), environment, AuthEventBus())).build()
        val releaseRefresh = java.util.concurrent.CountDownLatch(1)
        val rotationIssued = java.util.concurrent.CountDownLatch(1)
        if (refresh) {
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    if (request.path != "/oauth2/token") return MockResponse().setResponseCode(401)
                    assertTrue(request.body.readUtf8().contains("refresh_token=alice-refresh"))
                    val result = if (rejected) MockResponse().setResponseCode(400).setBody("""{"error":"invalid_grant"}""")
                        else MockResponse().setBody("""{"access_token":"rotated-alice","refresh_token":"rotated-refresh"}""")
                    rotationIssued.countDown()
                    check(releaseRefresh.await(5, TimeUnit.SECONDS))
                    return result
                }
            }
        } else {
            val result = MockResponse().setBody("alice-private-data")
            if (delayedBody) result.setBodyDelay(500, TimeUnit.MILLISECONDS) else result.setHeadersDelay(500, TimeUnit.MILLISECONDS)
            server.enqueue(result)
        }
        val executor = Executors.newSingleThreadExecutor()
        try {
            val asyncFailure = java.util.concurrent.CompletableFuture<IOException>()
            val request = Request.Builder().url(server.url("/private")).build()
            if (failExpiryCommit) client.newCall(request).enqueue(object : okhttp3.Callback {
                override fun onFailure(call: okhttp3.Call, e: IOException) { asyncFailure.complete(e) }
                override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                    response.close()
                    asyncFailure.completeExceptionally(AssertionError("Expected persistence failure"))
                }
            })
            val result = if (failExpiryCommit) null else executor.submit<Boolean> {
                try {
                    client.newCall(request).execute().use { it.body?.string() }
                    false
                } catch (_: IOException) { true }
            }
            assertNotNull(server.takeRequest(5, TimeUnit.SECONDS))
            if (refresh) {
                assertEquals("/oauth2/token", server.takeRequest(5, TimeUnit.SECONDS)!!.path)
                assertTrue(rotationIssued.await(5, TimeUnit.SECONDS))
            }
            if (delayedBody) assertTrue(headersObserved.await(5, TimeUnit.SECONDS))
            if (switchBeforeResult) tokens.switchProfile(bob)
            val selectedBob = tokens.snapshot()
            if (switchBackBeforeResult) tokens.switchProfile(alice.profileId!!)
            val selectedBeforeRelease = tokens.snapshot()
            failNextCommit = failRotationCommit || failExpiryCommit
            releaseRefresh.countDown()
            if (failExpiryCommit) {
                assertTrue(asyncFailure.get(5, TimeUnit.SECONDS) is TokenRefreshException)
                assertEquals(alice, tokens.snapshot())
                assertEquals(2, tokens.profiles.value.size)
                assertEquals("alice-refresh", tokens.getRefreshToken())
                val restarted = TokenStorage(prefs, server.url("/").toString())
                assertEquals(alice.profileId, restarted.snapshot().profileId)
                assertEquals(2, restarted.profiles.value.size)
                assertEquals("alice-refresh", restarted.getRefreshToken())
                assertThrows(IOException::class.java) { client.newCall(request).execute().close() }
                assertEquals("bob-refresh", TokenStorage(prefs, server.url("/").toString()).getRefreshToken())
                assertEquals(1, tokens.profiles.value.size)
                return
            }
            assertTrue(result!!.get(5, TimeUnit.SECONDS))
            if (!switchBackBeforeResult) assertEquals("bob-refresh", tokens.getRefreshToken())
            if (!switchBeforeResult) assertEquals(1, tokens.profiles.value.size)
            assertEquals(if (refresh) 2 else 1, server.requestCount)
            if (refresh && !rejected) {
                assertEquals(selectedBeforeRelease, tokens.snapshot())
                if (!switchBackBeforeResult) assertEquals(selectedBob, tokens.snapshot())
                tokens.switchProfile(alice.profileId!!)
                assertEquals("rotated-alice", tokens.getAccessToken())
                assertEquals("rotated-refresh", tokens.getRefreshToken())
                assertTrue(tokens.retryPendingRotation())
                val restarted = TokenStorage(prefs, server.url("/").toString())
                assertEquals(alice.profileId, restarted.snapshot().profileId)
                assertEquals("rotated-refresh", restarted.getRefreshToken())
                server.dispatcher = object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse {
                        assertEquals("Bearer rotated-alice", request.getHeader("Authorization"))
                        return MockResponse().setBody("fresh-private-data")
                    }
                }
                client.newCall(Request.Builder().url(server.url("/private")).build()).execute().use {
                    assertEquals("fresh-private-data", it.body!!.string())
                }
                server.dispatcher = object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse = when {
                        request.path == "/oauth2/token" -> {
                            assertTrue(request.body.readUtf8().contains("refresh_token=rotated-refresh"))
                            MockResponse().setBody("""{"access_token":"next-alice","refresh_token":"next-refresh"}""")
                        }
                        request.getHeader("Authorization") == "Bearer next-alice" -> MockResponse().setBody("next-private-data")
                        else -> MockResponse().setResponseCode(401)
                    }
                }
                client.newCall(Request.Builder().url(server.url("/private")).build()).execute().use {
                    assertEquals("next-private-data", it.body!!.string())
                }
                assertEquals("next-refresh", tokens.getRefreshToken())
            }
        } finally {
            releaseRefresh.countDown()
            executor.shutdownNow()
            server.shutdown()
        }
    }
}
