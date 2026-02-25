package dev.tuist.app.navigation

import kotlinx.serialization.Serializable

@Serializable
sealed class Routes {
    @Serializable
    data object Login : Routes()

    @Serializable
    data object Home : Routes()
}

@Serializable
sealed class HomeTabs {
    @Serializable
    data object Previews : HomeTabs()

    @Serializable
    data object Profile : HomeTabs()

    @Serializable
    data class PreviewDetail(
        val previewId: String,
        val fullHandle: String,
    ) : HomeTabs()
}
