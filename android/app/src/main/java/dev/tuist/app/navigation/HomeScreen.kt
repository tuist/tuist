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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dev.tuist.app.R
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.ui.notifications.NotificationsScreen
import dev.tuist.app.ui.previews.PreviewDetailScreen
import dev.tuist.app.ui.previews.PreviewsScreen
import dev.tuist.app.ui.profile.ProfileScreen
import dev.tuist.app.ui.threads.ThreadsScreen
import dev.tuist.app.ui.threads.ThreadsViewModel
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.semantics

@Composable
fun HomeScreen(navigation: AppNavigationViewModel, authState: AuthState) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val threadsViewModel: ThreadsViewModel = hiltViewModel()
    val threadsState by threadsViewModel.state.collectAsStateWithLifecycle()
    val pendingUrl by navigation.pendingUrl.collectAsStateWithLifecycle()

    LaunchedEffect(pendingUrl, authState) {
        val url = pendingUrl ?: return@LaunchedEffect
        val route = navigation.pendingRoute(authState) ?: return@LaunchedEffect
        navController.navigateAppRoute(route)
        navigation.consume(url)
    }
    val profilesViewModel: ProfilesViewModel = hiltViewModel()
    val choices by profilesViewModel.choices.collectAsStateWithLifecycle()
    val loading by profilesViewModel.loading.collectAsStateWithLifecycle()
    val failed by profilesViewModel.failed.collectAsStateWithLifecycle()
    val session by profilesViewModel.auth.session.collectAsStateWithLifecycle()
    var choosing by remember { mutableStateOf(false) }
    val chooserLabel = stringResource(R.string.profiles_title)

    LaunchedEffect(Unit) { profilesViewModel.load() }
    LaunchedEffect(choosing) { if (choosing) profilesViewModel.load() }
    if (choosing) AlertDialog(
        onDismissRequest = { choosing = false; profilesViewModel.cancelSelection() },
        title = { Text(chooserLabel) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                if (loading) Text(stringResource(R.string.organizations_loading))
                if (failed || choices.incomplete) Text(stringResource(R.string.organizations_failed))
                choices.organizations.forEach { choice ->
                    val active = choice.origin == session.origin && choice.logins.any { it.id == session.profileId } &&
                        (if (choice.personal) session.organization == null else choice.name == session.organization)
                    TextButton(enabled = !loading, onClick = {
                        profilesViewModel.select(choice, choice.preferredLogin(session.profileId).id) { choosing = false }
                    }) {
                        val name = if (choice.personal) stringResource(R.string.organizations_personal, choice.name) else choice.name
                        Text((if (active) "✓ " else "") + name + "\n" + choice.origin + "\n" + choice.logins.joinToString { it.label })
                    }
                }
                if (failed || choices.incomplete) TextButton(enabled = !loading, onClick = { profilesViewModel.load() }) {
                    Text(stringResource(R.string.organizations_retry))
                }
                TextButton(onClick = { choosing = false; profilesViewModel.cancelSelection(); profilesViewModel.auth.beginAddProfile() }) {
                    Text(stringResource(R.string.profiles_add))
                }
            }
        },
        confirmButton = { TextButton(onClick = { choosing = false; profilesViewModel.cancelSelection() }) { Text(stringResource(R.string.profiles_cancel)) } },
    )

    LaunchedEffect(threadsState.enabled) {
        if (!threadsState.enabled && currentDestination?.hasRoute<HomeTabs.Threads>() == true) {
            navController.navigate(HomeTabs.Previews) {
                popUpTo(HomeTabs.Previews) { inclusive = true }
                launchSingleTop = true
            }
        }
    }

    val showBottomBar = currentDestination?.hasRoute<HomeTabs.PreviewDetail>() != true &&
        currentDestination?.hasRoute<HomeTabs.Notifications>() != true

    Scaffold(
        bottomBar = {
            AnimatedVisibility(visible = showBottomBar) {
            NavigationBar {
                NavigationBarItem(
                    selected = currentDestination?.hierarchy?.any {
                        it.hasRoute<HomeTabs.Previews>()
                    } == true,
                    onClick = { navigation.open(AppRoute.Previews) },
                    icon = {
                        Icon(
                            painter = painterResource(R.drawable.ic_device_mobile),
                            contentDescription = null,
                        )
                    },
                    label = { Text(stringResource(R.string.previews_title)) },
                )
                if (threadsState.enabled) NavigationBarItem(
                    selected = currentDestination?.hasRoute<HomeTabs.Threads>() == true,
                    onClick = {
                        navController.navigate(HomeTabs.Threads) {
                            popUpTo(HomeTabs.Previews)
                            launchSingleTop = true
                        }
                    },
                    icon = { Icon(painterResource(R.drawable.ic_message), contentDescription = null) },
                    label = { Text(stringResource(R.string.threads_title)) },
                )
                NavigationBarItem(
                    selected = currentDestination?.hierarchy?.any {
                        it.hasRoute<HomeTabs.Profile>()
                    } == true,
                    modifier = Modifier
                        .semantics { onLongClick(chooserLabel) { choosing = true; true } }
                        .pointerInput(Unit) {
                            awaitEachGesture {
                                awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                                val held = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                                    waitForUpOrCancellation(PointerEventPass.Initial)
                                    false
                                } ?: true
                                if (held) {
                                    choosing = true
                                    do {
                                        val event = awaitPointerEvent(PointerEventPass.Initial)
                                        event.changes.forEach { it.consume() }
                                    } while (event.changes.any { it.pressed })
                                }
                            }
                        },
                    onClick = { navigation.open(AppRoute.Profile) },
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
                        navigation.preview(previewId, fullHandle)
                    },
                )
            }
            composable<HomeTabs.Profile> {
                ProfileScreen(
                    onNotificationsClick = { navController.navigate(HomeTabs.Notifications) },
                )
            }
            composable<HomeTabs.Notifications> {
                NotificationsScreen(onBack = { navController.popBackStack() })
            }
            composable<HomeTabs.Threads> {
                ThreadsScreen(threadsViewModel)
            }
            composable<HomeTabs.PreviewDetail> {
                PreviewDetailScreen(
                    onBack = { navController.popBackStack() },
                )
            }
        }
    }
}
