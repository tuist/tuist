package dev.tuist.app.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.tuist.app.ui.noora.Noora
import dev.tuist.app.ui.noora.NooraSpacing
import dev.tuist.app.ui.noora.NooraTheme

enum class SignInButtonStyle { PRIMARY, SECONDARY }

@Composable
fun SocialSignInButton(
    title: String,
    style: SignInButtonStyle,
    @DrawableRes iconRes: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(Noora.CornerRadius.Large)

    val semanticColors = NooraTheme.colors

    // Primary: gradient from a white-blended purple to buttonPrimaryBackground
    val backgroundBrush = when (style) {
        SignInButtonStyle.PRIMARY -> Brush.verticalGradient(
            colors = listOf(
                Color(0xFF854DFF),
                semanticColors.buttonPrimaryBackground,
            ),
        )
        SignInButtonStyle.SECONDARY -> SolidColor(semanticColors.buttonSecondaryBackground)
    }

    val borderColor = when (style) {
        SignInButtonStyle.PRIMARY -> Noora.Colors.Purple600.copy(alpha = 0.898f)
        SignInButtonStyle.SECONDARY -> Color.Black.copy(alpha = 0.08f)
    }

    val textColor = when (style) {
        SignInButtonStyle.PRIMARY -> semanticColors.buttonPrimaryLabel
        SignInButtonStyle.SECONDARY -> semanticColors.buttonSecondaryLabel
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                elevation = 1.5.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = 0.16f),
                spotColor = Color.Black.copy(alpha = 0.05f),
            )
            .clip(shape)
            .background(backgroundBrush)
            .border(1.dp, borderColor, shape)
            .clickable(onClick = onClick)
            .padding(vertical = NooraSpacing.Spacing5),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(NooraSpacing.Spacing1),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(
                painter = painterResource(iconRes),
                contentDescription = null,
                modifier = Modifier.size(NooraSpacing.Spacing7),
            )
            Text(
                text = title,
                color = textColor,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = NooraSpacing.Spacing2),
            )
        }
    }
}
