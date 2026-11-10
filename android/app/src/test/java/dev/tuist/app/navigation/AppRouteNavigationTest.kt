package dev.tuist.app.navigation

import android.app.Application
import android.os.Bundle
import androidx.lifecycle.ViewModelStore
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavHostController
import androidx.navigation.compose.ComposeNavigator
import androidx.navigation.compose.composable
import androidx.navigation.createGraph
import androidx.navigation.toRoute
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [28])
class AppRouteNavigationTest {
    private fun controller(saved: Bundle? = null): NavHostController =
        NavHostController(RuntimeEnvironment.getApplication()).apply {
            setViewModelStore(ViewModelStore())
            navigatorProvider.addNavigator(ComposeNavigator())
            if (saved != null) restoreState(saved)
            graph = createGraph(startDestination = HomeTabs.Previews) {
                composable<HomeTabs.Previews> {}
                composable<HomeTabs.Profile> {}
                composable<HomeTabs.PreviewDetail> {}
                composable<HomeTabs.Threads> {}
                composable<HomeTabs.Notifications> {}
            }
        }

    @Test
    fun `preview links from threads return Back to previews without retaining threads`() {
        val nav = controller()
        nav.navigate(HomeTabs.Threads)
        nav.navigateAppRoute(AppRoute.PreviewDetail("a", "p", "one"))
        assertEquals(HomeTabs.PreviewDetail("one", "a/p"), nav.currentBackStackEntry!!.toRoute<HomeTabs.PreviewDetail>())
        assertTrue(nav.popBackStack())
        assertTrue(nav.currentDestination!!.hasRoute<HomeTabs.Previews>())
        assertFalse(nav.popBackStack())
    }

    @Test
    fun `notifications retain profile Back and external routes replace the settings stack`() {
        val nav = controller()
        nav.navigateAppRoute(AppRoute.Profile)
        nav.navigate(HomeTabs.Notifications)
        assertTrue(nav.popBackStack())
        assertTrue(nav.currentDestination!!.hasRoute<HomeTabs.Profile>())
        nav.navigate(HomeTabs.Notifications)
        nav.navigateAppRoute(AppRoute.Profile)
        assertTrue(nav.popBackStack())
        assertTrue(nav.currentDestination!!.hasRoute<HomeTabs.Previews>())
        nav.navigateAppRoute(AppRoute.Profile)
        nav.navigate(HomeTabs.Notifications)
        nav.navigateAppRoute(AppRoute.Previews)
        assertTrue(nav.currentDestination!!.hasRoute<HomeTabs.Previews>())
        assertFalse(nav.popBackStack())
    }

    @Test
    fun `detail links replace prior detail and Back returns to previews`() {
        val nav = controller()
        nav.navigateAppRoute(AppRoute.Profile)
        nav.navigateAppRoute(AppRoute.PreviewDetail("a", "p", "one"))
        assertEquals(HomeTabs.PreviewDetail("one", "a/p"), nav.currentBackStackEntry!!.toRoute<HomeTabs.PreviewDetail>())
        val entryId = nav.currentBackStackEntry!!.id
        nav.navigateAppRoute(AppRoute.PreviewDetail("a", "p", "one"))
        assertEquals(entryId, nav.currentBackStackEntry!!.id)
        nav.navigateAppRoute(AppRoute.PreviewDetail("a", "p", "two"))
        assertTrue(nav.popBackStack())
        assertTrue(nav.currentDestination!!.hasRoute<HomeTabs.Previews>())
        assertFalse(nav.popBackStack())
    }

    @Test
    fun `root and profile entry points do not stack duplicates`() {
        val nav = controller()
        val rootId = nav.currentBackStackEntry!!.id
        nav.navigateAppRoute(AppRoute.Previews)
        assertEquals(rootId, nav.currentBackStackEntry!!.id)
        nav.navigateAppRoute(AppRoute.Profile)
        val profileId = nav.currentBackStackEntry!!.id
        nav.navigateAppRoute(AppRoute.Profile)
        assertEquals(profileId, nav.currentBackStackEntry!!.id)
        nav.navigateAppRoute(AppRoute.Previews)
        assertEquals(rootId, nav.currentBackStackEntry!!.id)
        assertFalse(nav.popBackStack())
    }

    @Test
    fun `canonical and handoff spellings target the same entry including after restoration`() {
        val nav = controller()
        val route = AppRoute.PreviewDetail("équipe", "mobile+app", "opaque+id")
        nav.navigateAppRoute(checkNotNull(AppRoute.parse(route.toUrl(), route.server)))
        val entryId = nav.currentBackStackEntry!!.id
        nav.navigateAppRoute(checkNotNull(AppRoute.parse(route.toHandoffUrl(), route.server)))
        assertEquals(entryId, nav.currentBackStackEntry!!.id)
        val restored = controller(nav.saveState())
        restored.navigateAppRoute(checkNotNull(AppRoute.parse(route.toUrl(), route.server)))
        assertEquals(entryId, restored.currentBackStackEntry!!.id)
        assertEquals(HomeTabs.PreviewDetail("opaque+id", "équipe/mobile+app"), restored.currentBackStackEntry!!.toRoute<HomeTabs.PreviewDetail>())
        assertTrue(restored.popBackStack())
        assertTrue(restored.currentDestination!!.hasRoute<HomeTabs.Previews>())
        assertFalse(restored.popBackStack())
    }

    @Test
    fun `restored detail retains Back destination without replaying a route`() {
        val nav = controller()
        nav.navigateAppRoute(AppRoute.PreviewDetail("a", "p", "opaque+id"))
        val restored = controller(nav.saveState())
        assertEquals(HomeTabs.PreviewDetail("opaque+id", "a/p"), restored.currentBackStackEntry!!.toRoute<HomeTabs.PreviewDetail>())
        assertTrue(restored.popBackStack())
        assertTrue(restored.currentDestination!!.hasRoute<HomeTabs.Previews>())
    }
}
