package dev.tuist.app.navigation

import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.content.pm.ServiceInfo
import android.os.Bundle
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [28])
class WebBrowserTest {
    private val url = "https://tuist.dev/acme/mobile/previews/latest?branch=main#build"
    private val launched = mutableListOf<Intent>()

    private fun context(defaultBrowser: String?, providers: List<String>): Context {
        val manager = mockk<PackageManager>()
        val context = mockk<Context>()
        every { context.packageManager } returns manager
        every { manager.resolveActivity(any<Intent>(), any<Int>()) } returns defaultBrowser?.let { browser ->
            ResolveInfo().apply { activityInfo = ActivityInfo().apply { packageName = browser } }
        }
        every { manager.queryIntentServices(any<Intent>(), any<Int>()) } returns providers.map { browser ->
            ResolveInfo().apply { serviceInfo = ServiceInfo().apply { packageName = browser } }
        }
        every { manager.resolveService(any<Intent>(), any<Int>()) } answers {
            firstArg<Intent>().`package`?.takeIf { it in providers }?.let { browser ->
                ResolveInfo().apply { serviceInfo = ServiceInfo().apply { packageName = browser } }
            }
        }
        every { context.startActivity(any<Intent>(), any<Bundle>()) } answers {
            launched.add(firstArg())
            Unit
        }
        return context
    }

    private fun assertLaunch(context: Context, browser: String) {
        assertTrue(context.openWebTab(url))
        assertEquals(1, launched.size)
        assertEquals(Intent.ACTION_VIEW, launched.single().action)
        assertEquals(url, launched.single().dataString)
        assertEquals(browser, launched.single().`package`)
    }

    @Test
    fun `installed provider opens when no default browser is set`() {
        assertLaunch(context(null, listOf("browser.customtabs")), "browser.customtabs")
    }

    @Test
    fun `installed provider opens when default is the Android resolver`() {
        assertLaunch(context("android", listOf("browser.customtabs")), "browser.customtabs")
    }

    @Test
    fun `installed provider opens when default browser does not support Custom Tabs`() {
        assertLaunch(context("browser.unsupported", listOf("browser.customtabs")), "browser.customtabs")
    }

    @Test
    fun `supported default is preferred over another installed provider`() {
        assertLaunch(
            context("browser.default", listOf("browser.other", "browser.default")),
            "browser.default",
        )
    }

    @Test
    fun `no providers returns failure without launching an unpinned intent`() {
        assertFalse(context("browser.unsupported", emptyList()).openWebTab(url))
        assertTrue(launched.isEmpty())
    }
}
