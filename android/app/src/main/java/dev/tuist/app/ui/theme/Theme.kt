package dev.tuist.app.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import dev.tuist.app.ui.noora.DarkSemanticColors
import dev.tuist.app.ui.noora.LightSemanticColors
import dev.tuist.app.ui.noora.LocalNooraColors
import dev.tuist.app.ui.noora.NooraColors

private val LightColorScheme = lightColorScheme(
    primary = NooraColors.Purple500,
    onPrimary = Color.White,
    primaryContainer = NooraColors.Purple100,
    onPrimaryContainer = NooraColors.Purple900,
    secondary = NooraColors.Purple400,
    onSecondary = Color.White,
    background = NooraColors.NeutralLight50,
    onBackground = NooraColors.NeutralLight1200,
    surface = NooraColors.NeutralLight50,
    onSurface = NooraColors.NeutralLight1200,
    surfaceVariant = NooraColors.NeutralLight200,
    onSurfaceVariant = NooraColors.NeutralLight800,
    outline = NooraColors.NeutralLight800,
)

private val DarkColorScheme = darkColorScheme(
    primary = NooraColors.Purple400,
    onPrimary = Color.White,
    primaryContainer = NooraColors.Purple800,
    onPrimaryContainer = NooraColors.Purple100,
    secondary = NooraColors.Purple300,
    onSecondary = Color.White,
    background = NooraColors.NeutralDark1200,
    onBackground = NooraColors.NeutralLight50,
    surface = NooraColors.NeutralDark1200,
    onSurface = NooraColors.NeutralLight50,
    surfaceVariant = NooraColors.NeutralDark1100,
    onSurfaceVariant = NooraColors.NeutralDark500,
    outline = NooraColors.NeutralDark500,
)

@Composable
fun TuistTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val semanticColors = if (darkTheme) DarkSemanticColors else LightSemanticColors

    CompositionLocalProvider(LocalNooraColors provides semanticColors) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = TuistTypography,
            content = content,
        )
    }
}
