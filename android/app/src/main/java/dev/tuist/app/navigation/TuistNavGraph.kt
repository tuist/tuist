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
import dev.tuist.app.ui.projects.ProjectsScreen
import kotlinx.coroutines.flow.StateFlow

@Composable
fun TuistNavGraph(
    authState: StateFlow<AuthState>,
) {
    val navController = rememberNavController()
    val currentAuthState by authState.collectAsStateWithLifecycle()

    LaunchedEffect(currentAuthState) {
        when (currentAuthState) {
            is AuthState.LoggedIn, is AuthState.Authenticating -> {
                navController.navigate(Routes.Projects) {
                    popUpTo(Routes.Login) { inclusive = true }
                }
            }
            is AuthState.LoggedOut -> {
                navController.navigate(Routes.Login) {
                    popUpTo(0) { inclusive = true }
                }
            }
        }
    }

    val startDestination: Routes = when (currentAuthState) {
        is AuthState.LoggedIn, is AuthState.Authenticating -> Routes.Projects
        is AuthState.LoggedOut -> Routes.Login
    }

    NavHost(
        navController = navController,
        startDestination = startDestination,
    ) {
        composable<Routes.Login> {
            LoginScreen()
        }
        composable<Routes.Projects> {
            ProjectsScreen()
        }
    }
}
