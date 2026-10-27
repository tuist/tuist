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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.hilt.navigation.compose.hiltViewModel
import dev.tuist.app.R
import dev.tuist.app.ui.components.SignInButtonStyle
import dev.tuist.app.ui.components.SocialSignInButton
import dev.tuist.app.ui.noora.NooraSpacing
import dev.tuist.app.ui.noora.NooraTheme

@Composable
fun LoginScreen(
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val activity = LocalContext.current as Activity
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) {
        viewModel.messages.collect { message ->
            snackbarHostState.showSnackbar(message)
        }
    }

    Scaffold(
        containerColor = Color.Transparent,
        snackbarHost = {
            SnackbarHost(snackbarHostState) { data ->
                Snackbar(
                    snackbarData = data,
                    containerColor = NooraTheme.colors.cardOverlayBackground,
                    contentColor = NooraTheme.colors.surfaceLabelPrimary,
                )
            }
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
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
                    modifier = Modifier.size(NooraSpacing.Spacing15),
                )

                Spacer(Modifier.height(NooraSpacing.Spacing9))

                Text(
                    text = stringResource(R.string.login_title),
                    style = MaterialTheme.typography.headlineLarge,
                    color = NooraTheme.colors.surfaceLabelPrimary,
                )

                Spacer(Modifier.height(NooraSpacing.Spacing5))

                Text(
                    text = stringResource(R.string.login_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = NooraTheme.colors.surfaceLabelPrimary,
                    textAlign = TextAlign.Center,
                )

                Spacer(Modifier.weight(1f))

                val cardShape = RoundedCornerShape(topStart = NooraSpacing.Spacing9, topEnd = NooraSpacing.Spacing9)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(cardShape)
                        .background(NooraTheme.colors.cardOverlayBackground)
                        .border(NooraSpacing.Spacing1, NooraTheme.colors.cardOverlayBorder, cardShape)
                        .padding(horizontal = NooraSpacing.Spacing8)
                        .padding(top = NooraSpacing.Spacing9)
                        .padding(bottom = NooraSpacing.Spacing9 + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()),
                ) {
                    Column {
                        SocialSignInButton(
                            title = stringResource(R.string.sign_in_tuist),
                            style = SignInButtonStyle.PRIMARY,
                            iconRes = R.drawable.tuist_logo,
                            onClick = { viewModel.signIn(activity) },
                        )

                        Spacer(Modifier.height(NooraSpacing.Spacing5))

                        SocialSignInButton(
                            title = stringResource(R.string.sign_in_apple),
                            style = SignInButtonStyle.SECONDARY,
                            iconRes = R.drawable.apple_logo,
                            onClick = { viewModel.signInWithApple(activity) },
                        )

                        Spacer(Modifier.height(NooraSpacing.Spacing5))

                        SocialSignInButton(
                            title = stringResource(R.string.sign_in_google),
                            style = SignInButtonStyle.SECONDARY,
                            iconRes = R.drawable.google_logo,
                            onClick = { viewModel.signInWithGoogle(activity) },
                        )

                        Spacer(Modifier.height(NooraSpacing.Spacing5))

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
}
