package dev.tuist.app.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.ui.login.LoginScreen
import kotlinx.coroutines.flow.StateFlow
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.stringResource
import dev.tuist.app.R

@Composable
fun TuistNavGraph(
    authState: StateFlow<AuthState?>,
    navigation: AppNavigationViewModel,
    profilesViewModel: ProfilesViewModel = hiltViewModel(),
) {
    val observedAuthState by authState.collectAsStateWithLifecycle()
    val currentAuthState = observedAuthState ?: return
    val navController = rememberNavController()
    val session by profilesViewModel.auth.session.collectAsStateWithLifecycle()
    val adding by profilesViewModel.auth.addingProfile.collectAsStateWithLifecycle()

    LaunchedEffect(currentAuthState is AuthState.LoggedIn, session) {
        when (currentAuthState) {
            is AuthState.LoggedIn -> {
                navController.navigate(Routes.Home) {
                    popUpTo(0) { inclusive = true }
                    launchSingleTop = true
                }
            }
            is AuthState.LoggedOut, is AuthState.Authenticating -> {
                navController.navigate(Routes.Login) {
                    popUpTo(0) { inclusive = true }
                }
            }
        }
    }

    val startDestination: Routes = when (currentAuthState) {
        is AuthState.LoggedIn -> Routes.Home
        is AuthState.LoggedOut, is AuthState.Authenticating -> Routes.Login
    }

    NavHost(
        navController = navController,
        startDestination = startDestination,
        enterTransition = { androidx.compose.animation.EnterTransition.None },
        exitTransition = { androidx.compose.animation.ExitTransition.None },
        popEnterTransition = { androidx.compose.animation.EnterTransition.None },
        popExitTransition = { androidx.compose.animation.ExitTransition.None },
    ) {
        composable<Routes.Login> {
            LoginScreen()
        }
        composable<Routes.Home> {
            HomeScreen(navigation = navigation, authState = currentAuthState)
        }
    }

    if (adding) Dialog(
        onDismissRequest = { profilesViewModel.auth.cancelAddProfile() },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Box(Modifier.fillMaxSize()) {
            LoginScreen()
            TextButton(
                onClick = { profilesViewModel.auth.cancelAddProfile() },
                modifier = Modifier.align(Alignment.TopEnd).statusBarsPadding(),
            ) { Text(stringResource(R.string.profiles_cancel)) }
        }
    }
}
