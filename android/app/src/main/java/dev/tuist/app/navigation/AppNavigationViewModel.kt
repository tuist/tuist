package dev.tuist.app.navigation

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.model.AuthState
import javax.inject.Inject

@HiltViewModel
class AppNavigationViewModel @Inject constructor(
    private val savedState: SavedStateHandle,
    private val environment: EnvironmentConfig,
) : ViewModel() {
    val pendingUrl = savedState.getStateFlow<String?>("pendingRoute", null)

    fun openUrl(url: String): Boolean {
        val route = AppRoute.parse(url, environment.serverUrl) ?: return false
        savedState["pendingRoute"] = route.toUrl()
        return true
    }

    fun open(route: AppRoute): Boolean = openUrl(route.toUrl())

    fun pendingRoute(authState: AuthState): AppRoute? =
        if (authState is AuthState.LoggedIn) pendingUrl.value?.let { AppRoute.parse(it, environment.serverUrl) } else null

    fun consume(url: String) {
        if (pendingUrl.value == url) savedState["pendingRoute"] = null
    }

    fun preview(previewId: String, fullHandle: String): Boolean {
        val parts = fullHandle.split("/")
        if (parts.size != 2) return false
        return runCatching {
            open(AppRoute.PreviewDetail(parts[0], parts[1], previewId, environment.serverUrl))
        }.getOrDefault(false)
    }
}
