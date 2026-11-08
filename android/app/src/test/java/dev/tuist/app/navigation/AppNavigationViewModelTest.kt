package dev.tuist.app.navigation

import androidx.lifecycle.SavedStateHandle
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.*
import org.junit.Test

class AppNavigationViewModelTest {
    private val environment = mockk<EnvironmentConfig> {
        every { serverUrl } returns "https://tuist.dev"
    }
    private val loggedIn = AuthState.LoggedIn(Account("person@example.com", "person"))

    @Test
    fun `latest valid route waits for strictly LoggedIn and consumes only once`() {
        val model = AppNavigationViewModel(SavedStateHandle(), environment)
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
        val original = AppNavigationViewModel(savedState, environment)
        original.preview("opaque+id", "account/project")
        val restoredState = SavedStateHandle(savedState.keys().associateWith { savedState.get<Any?>(it) })
        val restored = AppNavigationViewModel(restoredState, environment)
        assertNull(restored.pendingRoute(AuthState.Authenticating))
        assertEquals(AppRoute.PreviewDetail("account", "project", "opaque+id"), restored.pendingRoute(loggedIn))
        restored.consume(restored.pendingUrl.value!!)
        val consumedState = SavedStateHandle(restoredState.keys().associateWith { restoredState.get<Any?>(it) })
        assertNull(AppNavigationViewModel(consumedState, environment).pendingRoute(loggedIn))
    }

    @Test
    fun `internal and external detail entry points use the same canonical contract`() {
        val model = AppNavigationViewModel(SavedStateHandle(), environment)
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
}
