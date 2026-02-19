package dev.tuist.app.navigation

import kotlinx.serialization.Serializable

@Serializable
sealed class Routes {
    @Serializable
    data object Login : Routes()

    @Serializable
    data object Projects : Routes()
}
