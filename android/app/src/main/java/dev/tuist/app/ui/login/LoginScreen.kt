package dev.tuist.app.ui.login

import android.app.Activity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import dev.tuist.app.R
import dev.tuist.app.ui.components.SignInButtonStyle
import dev.tuist.app.ui.components.SocialSignInButton
import dev.tuist.app.ui.theme.TuistColors

@Composable
fun LoginScreen(
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val activity = LocalContext.current as Activity

    Box(modifier = Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(R.drawable.launch_background),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
        )

        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))

            Image(
                painter = painterResource(R.drawable.tuist_rounded_icon),
                contentDescription = stringResource(R.string.app_name),
                modifier = Modifier.size(80.dp),
            )

            Spacer(Modifier.height(32.dp))

            Text(
                text = stringResource(R.string.login_title),
                style = MaterialTheme.typography.headlineLarge,
                color = TuistColors.NeutralLight1200,
            )

            Spacer(Modifier.height(12.dp))

            Text(
                text = stringResource(R.string.login_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = TuistColors.NeutralLight1200,
                textAlign = TextAlign.Center,
            )

            Spacer(Modifier.weight(1f))

            val cardShape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(cardShape)
                    .background(Color.White.copy(alpha = 0.6f))
                    .border(2.dp, Color.White, cardShape)
                    .padding(horizontal = 24.dp)
                    .padding(top = 32.dp)
                    .padding(bottom = 32.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()),
            ) {
                Column {
                    SocialSignInButton(
                        title = stringResource(R.string.sign_in_tuist),
                        style = SignInButtonStyle.PRIMARY,
                        iconRes = R.drawable.tuist_logo,
                        onClick = { viewModel.signIn(activity) },
                    )

                    Spacer(Modifier.height(12.dp))

                    SocialSignInButton(
                        title = stringResource(R.string.sign_in_apple),
                        style = SignInButtonStyle.SECONDARY,
                        iconRes = R.drawable.apple_logo,
                        onClick = { viewModel.signInWithApple(activity) },
                    )

                    Spacer(Modifier.height(12.dp))

                    SocialSignInButton(
                        title = stringResource(R.string.sign_in_google),
                        style = SignInButtonStyle.SECONDARY,
                        iconRes = R.drawable.google_logo,
                        onClick = { viewModel.signInWithGoogle(activity) },
                    )

                    Spacer(Modifier.height(12.dp))

                    SocialSignInButton(
                        title = stringResource(R.string.sign_in_github),
                        style = SignInButtonStyle.SECONDARY,
                        iconRes = R.drawable.github_logo,
                        onClick = { viewModel.signInWithGitHub(activity) },
                    )
                }
            }
        }
    }
}
