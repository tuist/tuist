package dev.tuist.app.navigation

import androidx.navigation.NavController
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.toRoute

fun NavController.navigateAppRoute(route: AppRoute) {
    val current = currentBackStackEntry
    val alreadyThere = when (route) {
        AppRoute.Previews -> current?.destination?.hasRoute<HomeTabs.Previews>() == true
        AppRoute.Profile -> current?.destination?.hasRoute<HomeTabs.Profile>() == true
        is AppRoute.PreviewDetail -> current?.destination?.hasRoute<HomeTabs.PreviewDetail>() == true &&
            current.toRoute<HomeTabs.PreviewDetail>() == HomeTabs.PreviewDetail(route.previewId, "${route.account}/${route.project}")
    }
    if (alreadyThere) return
    when (route) {
        AppRoute.Previews -> popBackStack(HomeTabs.Previews, inclusive = false)
        AppRoute.Profile -> navigate(HomeTabs.Profile) {
            popUpTo(HomeTabs.Previews)
            launchSingleTop = true
        }
        is AppRoute.PreviewDetail -> navigate(
            HomeTabs.PreviewDetail(route.previewId, "${route.account}/${route.project}"),
        ) {
            popUpTo(HomeTabs.Previews)
            launchSingleTop = true
        }
    }
}
