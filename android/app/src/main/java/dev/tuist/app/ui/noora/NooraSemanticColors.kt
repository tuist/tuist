package dev.tuist.app.ui.noora

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

@Immutable
data class NooraSemanticColors(
    // Surface
    val surfaceOverlay: Color,
    val surfaceBackgroundPrimary: Color,
    val surfaceBackgroundSecondary: Color,
    val surfaceBackgroundTertiary: Color,

    // Label
    val surfaceLabelPrimary: Color,
    val surfaceLabelSecondary: Color,
    val surfaceLabelTertiary: Color,
    val surfaceLabelDestructive: Color,
    val surfaceLabelSuccess: Color,
    val surfaceLabelDisabled: Color,

    // Table
    val surfaceTableHeader: Color,

    // Button
    val buttonPrimaryBackground: Color,
    val buttonPrimaryLabel: Color,
    val buttonSecondaryBackground: Color,
    val buttonSecondaryLabel: Color,
    val buttonEnabledLabel: Color,
    val buttonEnabledBackground: Color,
    val buttonDisabledLabel: Color,
    val buttonDisabledBackground: Color,

    // Badge
    val badgeInformationLabel: Color,
    val badgeInformationBackground: Color,

    // Card
    val cardOverlayBackground: Color,
    val cardOverlayBorder: Color,

    // Accent
    val accent: Color,
)

val LightSemanticColors = NooraSemanticColors(
    surfaceOverlay = NooraColors.NeutralGray24Alpha,
    surfaceBackgroundPrimary = NooraColors.NeutralLight50,
    surfaceBackgroundSecondary = NooraColors.NeutralLight200,
    surfaceBackgroundTertiary = NooraColors.NeutralLight100,
    surfaceLabelPrimary = NooraColors.NeutralLight1200,
    surfaceLabelSecondary = NooraColors.NeutralLight800,
    surfaceLabelTertiary = NooraColors.NeutralLight700,
    surfaceLabelDestructive = NooraColors.Red500,
    surfaceLabelSuccess = NooraColors.Green500,
    surfaceLabelDisabled = NooraColors.NeutralLight600,
    surfaceTableHeader = NooraColors.NeutralLight200,
    buttonPrimaryBackground = NooraColors.Purple500,
    buttonPrimaryLabel = NooraColors.NeutralLight50,
    buttonSecondaryBackground = NooraColors.NeutralLight50,
    buttonSecondaryLabel = NooraColors.NeutralLight1200,
    buttonEnabledLabel = NooraColors.Purple500,
    buttonEnabledBackground = NooraColors.Purple500.copy(alpha = 0.15f),
    buttonDisabledLabel = Color(0xFF3C3C43).copy(alpha = 0.3f),
    buttonDisabledBackground = Color(0xFF787880).copy(alpha = 0.12f),
    badgeInformationLabel = NooraColors.Azure700,
    badgeInformationBackground = NooraColors.Azure50,
    cardOverlayBackground = Color.White.copy(alpha = 0.6f),
    cardOverlayBorder = Color.White,
    accent = NooraColors.Purple500,
)

val DarkSemanticColors = NooraSemanticColors(
    surfaceOverlay = NooraColors.NeutralGray16Alpha,
    surfaceBackgroundPrimary = NooraColors.NeutralDark1200,
    surfaceBackgroundSecondary = NooraColors.NeutralDark1100,
    surfaceBackgroundTertiary = NooraColors.NeutralDark1100,
    surfaceLabelPrimary = NooraColors.NeutralLight50,
    surfaceLabelSecondary = NooraColors.NeutralLight500,
    surfaceLabelTertiary = NooraColors.NeutralDark500,
    surfaceLabelDestructive = NooraColors.Red300,
    surfaceLabelSuccess = NooraColors.Green400,
    surfaceLabelDisabled = NooraColors.NeutralDark300,
    surfaceTableHeader = NooraColors.NeutralDark1000,
    buttonPrimaryBackground = NooraColors.Purple600,
    buttonPrimaryLabel = NooraColors.NeutralLight50,
    buttonSecondaryBackground = NooraColors.NeutralDark1100,
    buttonSecondaryLabel = NooraColors.NeutralLight50,
    buttonEnabledLabel = NooraColors.Purple400,
    buttonEnabledBackground = NooraColors.Purple500.copy(alpha = 0.20f),
    buttonDisabledLabel = Color(0xFF696C72).copy(alpha = 0.6f),
    buttonDisabledBackground = Color(0xFF787880).copy(alpha = 0.24f),
    badgeInformationLabel = NooraColors.Azure400,
    badgeInformationBackground = NooraColors.AzureAlpha,
    cardOverlayBackground = NooraColors.NeutralDark1200.copy(alpha = 0.8f),
    cardOverlayBorder = NooraColors.NeutralDark1100,
    accent = NooraColors.Purple400,
)

val LocalNooraColors = staticCompositionLocalOf { LightSemanticColors }
