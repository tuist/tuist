package dev.tuist.app.ui.noora

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable

object NooraTheme {
    val colors: NooraSemanticColors
        @Composable
        @ReadOnlyComposable
        get() = LocalNooraColors.current
}
