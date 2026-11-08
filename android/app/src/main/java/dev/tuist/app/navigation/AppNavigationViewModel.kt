package dev.tuist.app.navigation

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.TokenStorage
import dev.tuist.app.data.model.AuthState
import javax.inject.Inject

@HiltViewModel
class AppNavigationViewModel @Inject constructor(
    private val savedState: SavedStateHandle,
    private val tokens: TokenStorage,
) : ViewModel() {
    val pendingUrl = savedState.getStateFlow<String?>("pendingRoute", null)

    fun openUrl(url: String): Boolean {
        val route = AppRoute.parse(url, tokens.selectedServer()) ?: return false
        if (!allows(route)) return false
        savedState["pendingRoute"] = route.toUrl()
        savedState["pendingSession"] = sessionKey()
        savedState["pendingGeneration"] = tokens.snapshot().generation
        return true
    }

    fun open(route: AppRoute): Boolean = openUrl(route.toUrl())

    fun pendingRoute(authState: AuthState): AppRoute? {
        val url = pendingUrl.value ?: return null
        val owner = savedState.get<String>("pendingSession")
        val generation = savedState.get<Long>("pendingGeneration")
        val crossedLogin = owner == null && generation != null && tokens.snapshot().generation > generation + 1
        if (crossedLogin || (owner != null && owner != sessionKey())) {
            consume(url)
            return null
        }
        if (authState !is AuthState.LoggedIn) return null
        val route = AppRoute.parse(url, tokens.selectedServer())
        if (route == null || !allows(route)) {
            consume(url)
            return null
        }
        savedState["pendingSession"] = sessionKey()
        return route
    }

    private fun sessionKey(): String? = tokens.snapshot().let {
        if (it.profileId == null) null else listOf(it.profileId, it.generation, it.origin, it.organization).toString()
    }

    private fun allows(route: AppRoute): Boolean = route !is AppRoute.PreviewDetail ||
        tokens.snapshot().profileId == null || route.account == tokens.selectedAccount()

    fun isCurrentServerWebUrl(url: String): Boolean {
        val server = tokens.selectedServer()
        if (!AppRoute.isCurrentServerWebUrl(url, server)) return false
        return AppRoute.parse(url, server)?.let(::allows) ?: true
    }

    fun consume(url: String) {
        if (pendingUrl.value == url) {
            savedState["pendingRoute"] = null
            savedState["pendingSession"] = null
        }
    }

    fun preview(previewId: String, fullHandle: String): Boolean {
        val parts = fullHandle.split("/")
        if (parts.size != 2) return false
        return runCatching {
            open(AppRoute.PreviewDetail(parts[0], parts[1], previewId, tokens.selectedServer()))
        }.getOrDefault(false)
    }
}
