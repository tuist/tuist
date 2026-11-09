package dev.tuist.app.data.auth

import android.content.Context
import android.util.Base64
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.network.AuthInterceptor
import dev.tuist.app.data.network.SessionGuardInterceptor
import dev.tuist.app.data.network.TokenRefreshAuthenticator
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
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

@RunWith(RobolectricTestRunner::class)
class OrganizationRepositoryTest {
    private val prefs = RuntimeEnvironment.getApplication().getSharedPreferences("organizations-test", Context.MODE_PRIVATE)

    @Test fun `all saved memberships flatten by organization and exact origin with eligible login preference`() = runBlocking {
        prefs.edit().clear().commit()
        val first = MockWebServer()
        val second = MockWebServer()
        first.start()
        second.start()
        try {
            first.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest) = organizations(
                    if (request.getHeader("Authorization") == "Bearer ${jwt("alice")}") listOf("shared", "alpha") else listOf("shared", "beta"))
            }
            second.enqueue(organizations(listOf("shared")))
            TokenStorage(prefs, first.url("/").toString()).apply {
                storeTokens(jwt("alice"), "alice-refresh")
                storeTokens(jwt("bob"), "bob-refresh")
            }
            TokenStorage(prefs, second.url("/").toString()).storeTokens(jwt("carol"), "carol-refresh")
            val tokens = TokenStorage(prefs, first.url("/").toString())
            val alice = tokens.profiles.value.first { it.label.startsWith("alice") }
            val bob = tokens.profiles.value.first { it.label.startsWith("bob") }
            tokens.switchProfile(bob.id)
            val repository = OrganizationRepository(tokens, client(tokens, first))
            val result = repository.load()
            assertFalse(result.incomplete)
            assertEquals(4, result.organizations.size)
            val shared = result.organizations.single { it.name == "shared" && it.origin == first.url("/").toString() }
            assertEquals(listOf(alice.id, bob.id), shared.logins.map { it.id })
            assertEquals(bob.id, shared.preferredLogin(bob.id).id)
            assertEquals(alice.id, shared.preferredLogin("ineligible").id)
            assertEquals(2, result.organizations.count { it.name == "shared" })
            assertFalse(repository.validate(result.organizations.single { it.name == "alpha" }, bob.id))
            assertFalse(repository.validate(result.organizations.single { it.origin == second.url("/").toString() }, bob.id))
            assertEquals(bob.id, tokens.snapshot().profileId)
            assertEquals("beta", tokens.selectedAccount())
            val restarted = TokenStorage(prefs, first.url("/").toString())
            assertEquals("beta", restarted.selectedAccount())
            assertEquals(listOf("alpha", "shared"), restarted.profiles.value.first { it.id == alice.id }.memberships)
            restarted.switchProfile(alice.id)
            assertEquals("alpha", restarted.selectedAccount())
            val fence = restarted.snapshot()
            restarted.selectOrganization(alice.id, "shared")
            assertFalse(restarted.isCurrent(fence))
            restarted.switchProfile(bob.id)
            restarted.switchProfile(alice.id)
            assertEquals("shared", restarted.selectedAccount())
        } finally { first.shutdown(); second.shutdown() }
    }

    @Test fun `empty and unavailable memberships retain usable personal fallback without dropping credentials`() = runBlocking {
        prefs.edit().clear().commit()
        val server = MockWebServer()
        server.start()
        try {
            val tokens = TokenStorage(prefs, server.url("/").toString())
            tokens.storeTokens(jwt("alice"), "alice-refresh")
            tokens.storeTokens(jwt("bob"), "bob-refresh")
            val before = tokens.snapshot()
            server.enqueue(organizations(emptyList()))
            server.enqueue(MockResponse().setResponseCode(503))
            val result = OrganizationRepository(tokens, client(tokens, server)).load()
            assertTrue(result.incomplete)
            assertEquals(listOf("alice", "bob"), result.organizations.map { it.name })
            assertTrue(result.organizations.all { it.personal })
            assertEquals(before, tokens.snapshot())
            assertEquals("bob-refresh", tokens.getRefreshToken())
            assertEquals(2, tokens.profiles.value.size)
        } finally { server.shutdown() }
    }

    @Test fun `failed membership refresh preserves scope but successful empty response resets to personal`() = runBlocking {
        prefs.edit().clear().commit()
        val server = MockWebServer()
        server.start()
        try {
            val tokens = TokenStorage(prefs, server.url("/").toString())
            tokens.storeTokens(jwt("alice"), "alice-refresh")
            val repository = OrganizationRepository(tokens, client(tokens, server))
            server.enqueue(organizations(listOf("zulu", "alpha")))
            repository.load()
            assertEquals("alpha", tokens.selectedAccount())
            val scope = tokens.snapshot()
            server.enqueue(MockResponse().setResponseCode(503))
            val offline = repository.load()
            assertTrue(offline.incomplete)
            assertEquals(listOf("alice", "alpha", "zulu"), offline.organizations.map { it.name })
            val cached = offline.organizations.first { it.name == "alpha" }
            server.enqueue(MockResponse().setResponseCode(503))
            assertTrue(repository.validate(cached, scope.profileId!!))
            server.enqueue(MockResponse().setResponseCode(403))
            assertFalse(repository.validate(cached, scope.profileId!!))
            assertEquals(scope, tokens.snapshot())
            assertEquals(listOf("alpha", "zulu"), tokens.profiles.value.single().memberships)
            server.enqueue(organizations(emptyList()))
            assertTrue(repository.load().organizations.single().personal)
            assertEquals("alice", tokens.selectedAccount())
            assertFalse(tokens.isCurrent(scope))
            assertNull(tokens.snapshot().organization)
            val restarted = TokenStorage(prefs, server.url("/").toString())
            assertEquals("alice", restarted.selectedAccount())
            assertEquals(emptyList<String>(), restarted.profiles.value.single().memberships)
            assertEquals("alice-refresh", restarted.getRefreshToken())
        } finally { server.shutdown() }
    }

    @Test fun `inactive discovery refreshes only its owning credentials and normal requests route to selected origin`() = runBlocking {
        prefs.edit().clear().commit()
        val server = MockWebServer()
        server.start()
        try {
            val tokens = TokenStorage(prefs, server.url("/").toString())
            tokens.storeTokens(jwt("alice"), "alice-refresh")
            val alice = tokens.snapshot().profileId!!
            tokens.storeTokens(jwt("bob"), "bob-refresh")
            tokens.updateMemberships(tokens.snapshot().profileId!!, listOf("beta"))
            val before = tokens.snapshot()
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse = when {
                    request.path == "/oauth2/token" -> {
                        assertTrue(request.body.readUtf8().contains("refresh_token=alice-refresh"))
                        MockResponse().setBody("""{"access_token":"${jwt("alice", "rotated")}","refresh_token":"alice-new"}""")
                    }
                    request.getHeader("Authorization") == "Bearer ${jwt("alice")}" -> MockResponse().setResponseCode(401)
                    request.getHeader("Authorization") == "Bearer ${jwt("alice", "rotated")}" -> organizations(listOf("alpha"))
                    else -> organizations(listOf("beta"))
                }
            }
            val http = client(tokens, server)
            val result = OrganizationRepository(tokens, http).load()
            assertFalse(result.incomplete)
            assertEquals(before, tokens.snapshot())
            assertEquals("bob-refresh", tokens.getRefreshToken())
            assertEquals("alice-new", tokens.credentials(alice)?.refresh)
            assertTrue(http.newCall(Request.Builder().url("https://unused.invalid/api/organizations").build()).execute().use { it.isSuccessful })
            tokens.switchProfile(alice)
            assertEquals("alpha", tokens.selectedAccount())
            assertEquals("alice-new", TokenStorage(prefs, server.url("/").toString()).getRefreshToken())
        } finally { server.shutdown() }
    }

    @Test fun `other origin discovery and selected API refresh use saved URL and issuing client ID`() = runBlocking {
        prefs.edit().clear().commit()
        val first = MockWebServer()
        val other = MockWebServer()
        first.start()
        other.start()
        try {
            first.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest) = organizations(listOf("shared"))
            }
            val refreshes = java.util.concurrent.atomic.AtomicInteger()
            other.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    if (request.path == "/oauth2/token") {
                        val number = refreshes.incrementAndGet()
                        val body = request.body.readUtf8()
                        assertTrue(body.contains("client_id=other-origin-client"))
                        assertTrue(body.contains("refresh_token=" + if (number == 1) "alice-refresh" else "alice-refresh-1"))
                        return MockResponse().setBody("""{"access_token":"${jwt("alice", "rotation-$number")}","refresh_token":"alice-refresh-$number"}""")
                    }
                    if (request.getHeader("Authorization") == "Bearer ${jwt("alice")}") return MockResponse().setResponseCode(401)
                    if (request.path == "/api/organizations") return organizations(listOf("shared"))
                    if (request.getHeader("Authorization") == "Bearer ${jwt("alice", "rotation-1")}") return MockResponse().setResponseCode(401)
                    assertEquals("Bearer ${jwt("alice", "rotation-2")}", request.getHeader("Authorization"))
                    return MockResponse().setBody("other-origin-jam-data")
                }
            }
            TokenStorage(prefs, other.url("/").toString(), "other-origin-client").storeTokens(jwt("alice"), "alice-refresh")
            TokenStorage(prefs, first.url("/").toString(), "first-origin-client").storeTokens(jwt("bob"), "bob-refresh")
            val tokens = TokenStorage(prefs, first.url("/").toString(), "first-origin-client")
            val bob = tokens.snapshot().profileId
            val http = client(tokens, first)
            val choices = OrganizationRepository(tokens, http).load()
            assertFalse(choices.incomplete)
            assertEquals(2, choices.organizations.size)
            assertTrue(choices.organizations.all { it.name == "shared" })
            assertEquals(bob, tokens.snapshot().profileId)
            assertEquals("bob-refresh", tokens.getRefreshToken())
            val selected = choices.organizations.single { it.origin == other.url("/").toString() }
            tokens.selectOrganization(selected.logins.single().id, selected.name)
            val firstRequests = first.requestCount
            val body = http.newCall(Request.Builder().url(first.url("/api/accounts/alice/jams")).build()).execute().use { it.body!!.string() }
            assertEquals("other-origin-jam-data", body)
            assertEquals(firstRequests, first.requestCount)
            assertEquals(2, refreshes.get())
            assertEquals(other.url("/").toString(), tokens.snapshot().origin)
            assertEquals("alice-refresh-2", tokens.getRefreshToken())
            val restarted = TokenStorage(prefs, first.url("/").toString())
            assertEquals(other.url("/").toString(), restarted.selectedServer())
            assertEquals("other-origin-client", restarted.credentials(restarted.snapshot().profileId!!)?.clientId)
        } finally { first.shutdown(); other.shutdown() }
    }

    private fun client(tokens: TokenStorage, server: MockWebServer): OkHttpClient {
        val environment = mockk<EnvironmentConfig> {
            every { serverUrl } returns server.url("/").toString()
            every { oauthClientId } returns "android-client"
        }
        return OkHttpClient.Builder().addInterceptor(AuthInterceptor(tokens))
            .addNetworkInterceptor(SessionGuardInterceptor(tokens))
            .authenticator(TokenRefreshAuthenticator(tokens, OkHttpClient(), environment, AuthEventBus())).build()
    }

    private fun organizations(names: List<String>) = MockResponse().setBody(
        """{"organizations":[${names.joinToString { """{"name":"$it"}""" }}]}""")

    private fun jwt(subject: String, nonce: String = "initial"): String {
        val payload = """{"sub":"$subject","email":"$subject@example.invalid","preferred_username":"$subject","nonce":"$nonce"}"""
        return "header.${Base64.encodeToString(payload.toByteArray(), Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)}.fixture"
    }
}
