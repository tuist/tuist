package dev.tuist.app.ui.threads

import android.content.Intent
import android.graphics.Bitmap
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ThreadsScreenTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test
    fun modelFailureCanRecoverWithoutLosingTheDraft() {
        withPreview("error") {
            assertFalse(actionNode("Start thread").isEnabled)
            click("Try again")
            eventually { find("Models are temporarily unavailable").isEmpty() }
            click("Choose a model")
            click("Sample ChatGPT model")
            assertTrue(actionNode("Start thread").isEnabled)
            eventually { find("Add a flaky-test filter to the test results page.").isNotEmpty() }
            capture("recovered-draft")
        }
    }

    @Test
    fun suggestionsOnlyFillTheComposerAndArchiveDisablesIt() {
        withPreview("conversation") {
            click("Show the changes")
            eventually { find("Show the changes").any { it.isEditable } }
            click("Thread actions")
            click("Archive thread")
            eventually {
                find("This thread is archived. Restore it from the menu to continue.").isNotEmpty()
            }
            eventually { find("Send message").isEmpty() }
            capture("archived")
        }
    }

    @Test
    fun interruptedThreadsEnableFollowUpsButUnknownOutcomesStayBlocked() {
        withPreview("interrupted") {
            assertTrue(
                nodes(instrumentation.uiAutomation.rootInActiveWindow)
                    .single { it.isEditable }
                    .isEnabled
            )
            click("Show the changes")
            eventually { actionNode("Send message").isEnabled }
        }
        withPreview("outcome-unknown") {
            assertFalse(
                nodes(instrumentation.uiAutomation.rootInActiveWindow)
                    .single { it.isEditable }
                    .isEnabled
            )
            assertFalse(actionNode("Send message").isEnabled)
        }
    }

    @Test
    fun sampleShippingIsNeverActionable() {
        withPreview("ship") {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            scroll(root)
            instrumentation.waitForIdleSync()
            Thread.sleep(300)
            assertFalse(actionNode("Approve and ship").isEnabled)
            capture("ship-bottom")
        }
    }

    @Test
    fun deniedOrganizationCanReturnToThePersonalAccount() {
        withPreview("denied") {
            capture("denied")
            click("Back to personal account")
            eventually { find("Make something happen").isNotEmpty() }
            assertTrue(find("sample-user").isNotEmpty())
            assertTrue(find("Make flaky tests easier to find").isEmpty())
        }
    }

    @Test
    fun representativeScreensRenderInLightAndDark() {
        for (screen in
            listOf(
                "list",
                "new",
                "models",
                "error",
                "empty-models",
                "loading",
                "conversation",
                "reconnecting",
                "details",
                "ship",
                "flag-off",
            )) {
            withPreview(screen) {
                if (screen == "flag-off") assertTrue(find("Threads").isEmpty())
                capture(screen)
            }
        }
        withPreview("conversation", dark = true) { capture("conversation-dark") }
        withPreview("error", dark = true) { capture("error-dark") }
    }

    private fun withPreview(screen: String, dark: Boolean = false, block: () -> Unit) {
        val intent =
            Intent()
                .setClassName(
                    instrumentation.targetContext,
                    "dev.tuist.app.ui.threads.ThreadsPreviewActivity",
                )
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra("screen", screen)
                .putExtra("dark", dark)
        val activity = instrumentation.startActivitySync(intent)
        try {
            instrumentation.waitForIdleSync()
            Thread.sleep(650)
            block()
        } catch (error: Throwable) {
            capture("failure-$screen")
            throw error
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
            instrumentation.waitForIdleSync()
        }
    }

    private fun nodes(node: AccessibilityNodeInfo?): List<AccessibilityNodeInfo> =
        if (node == null) emptyList()
        else listOf(node) + (0 until node.childCount).flatMap { nodes(node.getChild(it)) }

    private fun find(text: String) =
        nodes(instrumentation.uiAutomation.rootInActiveWindow).filter {
            it.text?.toString() == text || it.contentDescription?.toString() == text
        }

    private fun eventually(predicate: () -> Boolean) {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!predicate() && System.nanoTime() < deadline) Thread.sleep(100)
        assertTrue(predicate())
    }

    private fun actionNode(text: String): AccessibilityNodeInfo {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (find(text).isEmpty() && System.nanoTime() < deadline) Thread.sleep(100)
        var node =
            find(text).firstOrNull()
                ?: error(
                    "Missing accessibility element: $text; visible: " +
                        nodes(instrumentation.uiAutomation.rootInActiveWindow).mapNotNull {
                            it.text?.toString()
                        }
                )
        while (!node.isClickable && node.parent != null) node = node.parent
        return node
    }

    private fun click(text: String) {
        assertTrue(actionNode(text).performAction(AccessibilityNodeInfo.ACTION_CLICK))
        instrumentation.waitForIdleSync()
        Thread.sleep(350)
    }

    private fun scroll(root: AccessibilityNodeInfo?) {
        nodes(root).firstOrNull {
            it.isScrollable && it.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
        }
    }

    private fun capture(name: String) {
        val directory =
            File(instrumentation.targetContext.getExternalFilesDir(null), "threads-screenshots")
                .apply { mkdirs() }
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: error("No screenshot")
        File(directory, "$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }
}
