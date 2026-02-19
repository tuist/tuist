package dev.tuist.app.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val LightColorScheme = lightColorScheme(
    primary = TuistColors.Purple500,
    onPrimary = Color.White,
    primaryContainer = TuistColors.Purple100,
    onPrimaryContainer = TuistColors.Purple900,
    secondary = TuistColors.Purple400,
    onSecondary = Color.White,
    background = TuistColors.NeutralLight50,
    onBackground = TuistColors.NeutralLight1200,
    surface = TuistColors.NeutralLight50,
    onSurface = TuistColors.NeutralLight1200,
    surfaceVariant = TuistColors.NeutralLight200,
    onSurfaceVariant = TuistColors.NeutralLight800,
    outline = TuistColors.NeutralLight800,
)

private val DarkColorScheme = darkColorScheme(
    primary = TuistColors.Purple400,
    onPrimary = Color.White,
    primaryContainer = TuistColors.Purple800,
    onPrimaryContainer = TuistColors.Purple100,
    secondary = TuistColors.Purple300,
    onSecondary = Color.White,
    background = TuistColors.NeutralDark1200,
    onBackground = TuistColors.NeutralLight50,
    surface = TuistColors.NeutralDark1200,
    onSurface = TuistColors.NeutralLight50,
    surfaceVariant = TuistColors.NeutralDark1100,
    onSurfaceVariant = TuistColors.NeutralDark500,
    outline = TuistColors.NeutralDark500,
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

    MaterialTheme(
        colorScheme = colorScheme,
        typography = TuistTypography,
        content = content,
    )
}
