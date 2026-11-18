package dev.tuist.app.ui.previews

import android.content.ContextWrapper
import android.content.Intent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tuist.app.R
import dev.tuist.app.api.model.Preview
import dev.tuist.app.navigation.AppRoute
import dev.tuist.app.ui.theme.TuistTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PreviewDetailScreenTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun webAndShareActionsUseTheSameCanonicalUrlWithoutAppLinkRecursion() {
        val intents = mutableListOf<Intent>()
        val context = object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) {
            override fun startActivity(intent: Intent, options: android.os.Bundle?) { intents.add(intent) }
            override fun startActivity(intent: Intent) { intents.add(intent) }
        }
        val route = AppRoute.PreviewDetail("équipe", "ios+android", "build%?#42", "https://TUist.dev:443/base/")
        val canonicalUrl = "https://tuist.dev/base/%C3%A9quipe/ios%2Bandroid/previews/build%25%3F%2342"
        val preview = Preview(
            builds = emptyList(), createdFromCi = true, deviceUrl = "", iconUrl = "",
            id = route.previewId, insertedAt = "2026-11-06T10:00:00Z", qrCodeUrl = "",
            supportedPlatforms = listOf("android", "ios"), url = "",
            displayName = "Tuist", version = "1.0.0", bundleIdentifier = "dev.tuist.app", gitBranch = "main",
        )
        compose.setContent {
            CompositionLocalProvider(LocalContext provides context) {
                TuistTheme {
                    PreviewDetailScreenContent(
                        PreviewDetailUiState.Success(preview), "${route.account}/${route.project}", route.server,
                        onBack = {}, onDelete = {}, onRetry = {},
                    )
                }
            }
        }
        val openOnWeb = context.getString(R.string.preview_open_on_web)
        val share = context.getString(R.string.share)
        compose.onNodeWithText(openOnWeb).assertIsDisplayed()
        compose.onNodeWithContentDescription(share).assertIsDisplayed()
        compose.onNodeWithText(openOnWeb).performClick()
        compose.runOnIdle {
            val browser = intents.single()
            assertEquals(Intent.ACTION_VIEW, browser.action)
            assertEquals(canonicalUrl, browser.dataString)
            assertNotNull(browser.`package`)
            assertNotEquals(context.packageName, browser.`package`)
            assertTrue(browser.hasExtra("android.support.customtabs.extra.SESSION"))
            intents.clear()
        }
        compose.onNodeWithContentDescription(share).performClick()
        compose.runOnIdle {
            val chooser = intents.single()
            assertEquals(Intent.ACTION_CHOOSER, chooser.action)
            @Suppress("DEPRECATION")
            val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
            assertEquals(Intent.ACTION_SEND, send.action)
            assertEquals("text/plain", send.type)
            assertEquals(canonicalUrl, send.getStringExtra(Intent.EXTRA_TEXT))
        }
    }
}
