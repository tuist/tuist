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

@Composable
fun TuistNavGraph(
    authState: StateFlow<AuthState?>,
    navigation: AppNavigationViewModel,
) {
    val observedAuthState by authState.collectAsStateWithLifecycle()
    val currentAuthState = observedAuthState ?: return
    val navController = rememberNavController()

    LaunchedEffect(currentAuthState) {
        when (currentAuthState) {
            is AuthState.LoggedIn -> {
                navController.navigate(Routes.Home) {
                    popUpTo(Routes.Login) { inclusive = true }
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
    ) {
        composable<Routes.Login> {
            LoginScreen()
        }
        composable<Routes.Home> {
            HomeScreen(navigation = navigation, authState = currentAuthState)
        }
    }
}
