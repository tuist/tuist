package dev.tuist.app.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dev.tuist.app.R
import dev.tuist.app.ui.previews.PreviewDetailScreen
import dev.tuist.app.ui.previews.PreviewsScreen
import dev.tuist.app.ui.profile.ProfileScreen

@Composable
fun HomeScreen() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    val showBottomBar = currentDestination?.hasRoute<HomeTabs.PreviewDetail>() != true

    Scaffold(
        bottomBar = {
            AnimatedVisibility(visible = showBottomBar) {
            NavigationBar {
                NavigationBarItem(
                    selected = currentDestination?.hierarchy?.any {
                        it.hasRoute<HomeTabs.Previews>()
                    } == true,
                    onClick = {
                        navController.navigate(HomeTabs.Previews) {
                            popUpTo(HomeTabs.Previews) { inclusive = true }
                            launchSingleTop = true
                        }
                    },
                    icon = {
                        Icon(
                            painter = painterResource(R.drawable.ic_device_mobile),
                            contentDescription = null,
                        )
                    },
                    label = { Text(stringResource(R.string.previews_title)) },
                )
                NavigationBarItem(
                    selected = currentDestination?.hierarchy?.any {
                        it.hasRoute<HomeTabs.Profile>()
                    } == true,
                    onClick = {
                        navController.navigate(HomeTabs.Profile) {
                            popUpTo(HomeTabs.Previews)
                            launchSingleTop = true
                        }
                    },
                    icon = {
                        if (currentDestination?.hierarchy?.any { it.hasRoute<HomeTabs.Profile>() } == true) {
                            Icon(Icons.Filled.Person, contentDescription = null)
                        } else {
                            Icon(Icons.Outlined.Person, contentDescription = null)
                        }
                    },
                    label = { Text(stringResource(R.string.profile_title)) },
                )
            }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = HomeTabs.Previews,
            modifier = Modifier.padding(padding),
        ) {
            composable<HomeTabs.Previews> {
                PreviewsScreen(
                    onPreviewClick = { previewId, fullHandle ->
                        navController.navigate(HomeTabs.PreviewDetail(previewId, fullHandle))
                    },
                )
            }
            composable<HomeTabs.Profile> {
                ProfileScreen()
            }
            composable<HomeTabs.PreviewDetail> {
                PreviewDetailScreen(
                    onBack = { navController.popBackStack() },
                )
            }
        }
    }
}
