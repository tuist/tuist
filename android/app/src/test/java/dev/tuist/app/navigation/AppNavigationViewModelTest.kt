package dev.tuist.app.navigation

import androidx.lifecycle.SavedStateHandle
import dev.tuist.app.data.auth.TokenStorage
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.*
import org.junit.Test

class AppNavigationViewModelTest {
    private var session = TokenStorage.Session("login", 1, "account", "https://tuist.dev")
    private val tokens = mockk<TokenStorage> {
        every { selectedServer() } answers { this@AppNavigationViewModelTest.session.origin ?: "https://tuist.dev" }
        every { selectedAccount() } answers { this@AppNavigationViewModelTest.session.organization ?: "account" }
        every { snapshot() } answers { this@AppNavigationViewModelTest.session }
    }
    private val loggedIn = AuthState.LoggedIn(Account("person@example.com", "person"))

    @Test
    fun `latest valid route waits for strictly LoggedIn and consumes only once`() {
        val model = AppNavigationViewModel(SavedStateHandle(), tokens)
        assertTrue(model.open(AppRoute.Previews))
        assertTrue(model.open(AppRoute.Profile))
        assertFalse(model.openUrl("tuist://app/a/p/previews/id?server=https%3A%2F%2Fwrong.dev"))
        assertFalse(model.openUrl("tuist://app/profile/extra"))
        assertNull(model.pendingRoute(AuthState.LoggedOut))
        assertNull(model.pendingRoute(AuthState.Authenticating))
        assertEquals(AppRoute.Profile, model.pendingRoute(loggedIn))
        model.consume(AppRoute.Previews.toUrl())
        assertEquals(AppRoute.Profile, model.pendingRoute(loggedIn))
        model.consume(model.pendingUrl.value!!)
        assertNull(model.pendingRoute(loggedIn))
        assertNull(model.pendingUrl.value)
    }

    @Test
    fun `saved pending route survives recreation but consumed route does not`() {
        val savedState = SavedStateHandle()
        val original = AppNavigationViewModel(savedState, tokens)
        original.preview("opaque+id", "account/project")
        val restoredState = SavedStateHandle(savedState.keys().associateWith { savedState.get<Any?>(it) })
        val restored = AppNavigationViewModel(restoredState, tokens)
        assertNull(restored.pendingRoute(AuthState.Authenticating))
        assertEquals(AppRoute.PreviewDetail("account", "project", "opaque+id"), restored.pendingRoute(loggedIn))
        restored.consume(restored.pendingUrl.value!!)
        val consumedState = SavedStateHandle(restoredState.keys().associateWith { restoredState.get<Any?>(it) })
        assertNull(AppNavigationViewModel(consumedState, tokens).pendingRoute(loggedIn))
    }

    @Test
    fun `internal and external detail entry points use the same canonical contract`() {
        val model = AppNavigationViewModel(SavedStateHandle(), tokens)
        assertTrue(model.preview("opaque-id", "account/project"))
        val internal = model.pendingUrl.value
        assertEquals("https://tuist.dev/account/project/previews/opaque-id", internal)
        model.consume(internal!!)
        assertTrue(model.openUrl("https://tuist.dev/account/project/previews/opaque-id"))
        assertEquals(internal, model.pendingUrl.value)
        assertTrue(model.openUrl("tuist://app/account/project/previews/opaque-id"))
        assertEquals(internal, model.pendingUrl.value)
        assertFalse(model.openUrl("https://tuist.dev/account/project/previews/latest"))
        assertFalse(model.openUrl("https://tuist.dev/account/project/previews/opaque-id/download"))
        assertEquals(internal, model.pendingUrl.value)
        assertFalse(model.preview("id", "a/p/extra"))
        assertFalse(model.preview("bad/id", "a/p"))
    }

    @Test
    fun `saved origin governs detail entry points across organizations`() {
        session = session.copy(origin = "https://other.dev", organization = "org")
        val model = AppNavigationViewModel(SavedStateHandle(), tokens)
        assertTrue(model.preview("id", "org/project"))
        assertEquals("https://other.dev/org/project/previews/id", model.pendingUrl.value)
        assertTrue(model.preview("id", "account/project"))
        assertFalse(model.openUrl("https://tuist.dev/org/project/previews/id"))
        assertTrue(model.openUrl("https://other.dev/account/project/previews/id"))
        assertEquals(AppRoute.PreviewDetail("account", "project", "id", "https://other.dev"), model.pendingRoute(loggedIn))
        assertTrue(model.isCurrentServerWebUrl("https://other.dev/account/project/previews/id"))
        assertTrue(model.openUrl("https://other.dev/org/project/previews/id"))
        assertTrue(model.isCurrentServerWebUrl("https://other.dev/org/project/previews/id"))
        assertFalse(model.isCurrentServerWebUrl("tuist://app/org/project/previews/id?server=https%3A%2F%2Fother.dev"))
        assertFalse(model.isCurrentServerWebUrl("tuist://app/account/project/previews/id?server=https%3A%2F%2Fother.dev"))
        assertFalse(model.isCurrentServerWebUrl("https://tuist.dev/org/project/previews/id"))
        assertFalse(model.openUrl("https://other.dev/web-only"))
        assertTrue(model.isCurrentServerWebUrl("https://other.dev/web-only"))
        assertFalse(model.isCurrentServerWebUrl("https://tuist.dev/web-only"))
    }

    @Test
    fun `pending routes cannot cross organization profile or signout transitions`() {
        val model = AppNavigationViewModel(SavedStateHandle(), tokens)
        listOf(
            session.copy(generation = 2, organization = "other"),
            session.copy(generation = 3, profileId = "other"),
            TokenStorage.Session(null, 4),
        ).forEach { next ->
            model.open(AppRoute.Profile)
            session = next
            assertNull(model.pendingRoute(loggedIn))
            assertNull(model.pendingUrl.value)
        }
    }

    @Test
    fun `cold login link survives authentication across organizations on same origin`() {
        session = TokenStorage.Session(null, 0)
        val model = AppNavigationViewModel(SavedStateHandle(), tokens)
        assertTrue(model.openUrl("https://tuist.dev/account/project/previews/id"))
        assertNull(model.pendingRoute(AuthState.Authenticating))
        session = TokenStorage.Session("login", 1, "account", "https://tuist.dev")
        assertNotNull(model.pendingRoute(loggedIn))
        session = session.copy(generation = 2)
        assertNull(model.pendingRoute(loggedIn))
        session = TokenStorage.Session(null, 3)
        assertTrue(model.openUrl("https://tuist.dev/account/project/previews/id"))
        session = TokenStorage.Session("login", 4, "wrong", "https://tuist.dev")
        assertEquals(AppRoute.PreviewDetail("account", "project", "id"), model.pendingRoute(loggedIn))
    }

    @Test
    fun `cold pending links cannot survive a login followed by a switch before delivery`() {
        session = TokenStorage.Session(null, 0)
        val model = AppNavigationViewModel(SavedStateHandle(), tokens)
        assertTrue(model.open(AppRoute.Profile))
        session = TokenStorage.Session("other-login", 2, "account", "https://tuist.dev")
        assertNull(model.pendingRoute(loggedIn))
        assertNull(model.pendingUrl.value)
    }
}
