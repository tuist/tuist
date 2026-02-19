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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.tuist.app.ui.theme.TuistColors

enum class SignInButtonStyle { PRIMARY, SECONDARY }

@Composable
fun SocialSignInButton(
    title: String,
    style: SignInButtonStyle,
    @DrawableRes iconRes: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(8.dp)

    // Primary: iOS uses purple500 (#6F2CFF) with a white overlay at 16% opacity at top fading to clear.
    // #6F2CFF blended with 16% white ≈ #854DFF
    val backgroundBrush = when (style) {
        SignInButtonStyle.PRIMARY -> Brush.verticalGradient(
            colors = listOf(
                Color(0xFF854DFF),
                TuistColors.Purple500,
            ),
        )
        SignInButtonStyle.SECONDARY -> Brush.verticalGradient(
            colors = listOf(
                Color(0xFFFDFDFD),
                Color(0xFFF7F7F8),
            ),
        )
    }

    val borderColor = when (style) {
        SignInButtonStyle.PRIMARY -> Color(0xFF5F01E5).copy(alpha = 0.898f)
        SignInButtonStyle.SECONDARY -> Color.Black.copy(alpha = 0.08f)
    }

    val textColor = when (style) {
        SignInButtonStyle.PRIMARY -> Color(0xFFFDFDFD)
        SignInButtonStyle.SECONDARY -> TuistColors.NeutralLight1200
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
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(
                painter = painterResource(iconRes),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = title,
                color = textColor,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }
    }
}
