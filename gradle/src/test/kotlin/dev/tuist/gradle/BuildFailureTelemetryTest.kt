package dev.tuist.gradle

import org.gradle.api.internal.tasks.execution.ExecuteTaskBuildOperationType
import org.gradle.api.tasks.VerificationException
import org.gradle.configuration.project.ConfigureProjectBuildOperationType
import org.junit.jupiter.api.Test
import org.gradle.api.tasks.TaskExecutionException
import org.gradle.internal.exceptions.DefaultMultiCauseException
import java.io.IOException
import java.lang.reflect.Proxy
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BuildFailureTelemetryTest {
    private fun taskDetails(): ExecuteTaskBuildOperationType.Details =
        Proxy.newProxyInstance(javaClass.classLoader, arrayOf(ExecuteTaskBuildOperationType.Details::class.java)) { _, _, _ -> null }
            as ExecuteTaskBuildOperationType.Details

    @Test fun `recovered nested cache failures do not change build status`() {
        val telemetry = BuildFailureTelemetry()
        telemetry.finished(null, IOException("unavailable cache"))
        assertFalse(telemetry.buildFailed)
        assertEquals(BuildCustomMetadata(), telemetry.metadata(BuildCustomMetadata()))
    }

    @Test fun `infrastructure failure wins over verification in the category`() {
        val telemetry = BuildFailureTelemetry()
        telemetry.finished(taskDetails(), VerificationException("private test diagnostic"))
        telemetry.finished(taskDetails(), IOException("private server address"))
        telemetry.finished(taskDetails(), VerificationException("another failed test"))
        assertTrue(telemetry.buildFailed)
        assertEquals(mapOf("tuist.detected_failure_category" to "infrastructure_tooling"), telemetry.metadata(BuildCustomMetadata()).values)
    }

    @Test fun `arbitrary failed tasks remain unknown`() {
        val telemetry = BuildFailureTelemetry()
        telemetry.finished(taskDetails(), IllegalStateException("script failed"))
        assertTrue(telemetry.buildFailed)
        assertNull(telemetry.metadata(BuildCustomMetadata()).values["tuist.detected_failure_category"])
    }

    @Test fun `configuration failures remain tooling failures even when the cause is verification`() {
        val details = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(ConfigureProjectBuildOperationType.Details::class.java)) { _, _, _ -> null }
            as ConfigureProjectBuildOperationType.Details
        val telemetry = BuildFailureTelemetry()
        telemetry.finished(details, VerificationException("build script failed"))
        assertTrue(telemetry.buildFailed)
        assertEquals("infrastructure_tooling", telemetry.metadata(BuildCustomMetadata()).values["tuist.detected_failure_category"])
    }

    @Test fun `existing metadata and explicit overrides are preserved`() {
        val telemetry = BuildFailureTelemetry()
        telemetry.finished(taskDetails(), VerificationException("check failed"))
        val existing = BuildCustomMetadata(values = mapOf("tuist.failure_category" to "infrastructure_tooling", "team" to "mobile"))
        assertEquals("infrastructure_tooling", telemetry.metadata(existing).values["tuist.failure_category"])
        assertEquals("mobile", telemetry.metadata(existing).values["team"])
        val full = BuildCustomMetadata(values = (1..MAX_BUILD_METADATA_VALUES).associate { "key$it" to "value$it" })
        assertEquals(full, telemetry.metadata(full))
    }

    @Test fun `renders the cause chain like the console without repeating wrapped messages`() {
        val cause = IllegalStateException("Compilation failed; see the compiler output below.\n/work/app/src/Broken.java:1: error: ';' expected")
        val wrapper = RuntimeException(cause.message, cause)
        val failure = RuntimeException("Execution failed for task ':compileJava'.", wrapper)
        val report = BuildFailureTelemetry.render(failure, "/work/app")
        assertEquals(
            "Execution failed for task ':compileJava'.\n> Compilation failed; see the compiler output below.\n  src/Broken.java:1: error: ';' expected",
            report.message
        )
        assertFalse(report.truncated)
    }

    @Test fun `renders every cause of a multi-cause failure and relativizes file URLs`() {
        val failure = DefaultMultiCauseException("Build failed.", listOf(
            IllegalStateException("There were failing tests. See the report at: file:///work/app/build/reports/tests/test/index.html"),
            IllegalStateException("Lint found errors in /work/app")
        ))
        assertEquals(
            "Build failed.\n> There were failing tests. See the report at: build/reports/tests/test/index.html\n> Lint found errors in .",
            BuildFailureTelemetry.render(failure, "/work/app").message
        )
        assertEquals("/work/application/x", BuildFailureTelemetry.relativize("/work/application/x", "/work/app"))
    }

    @Test fun `uses the exception class when a failure has no message`() {
        assertEquals("java.lang.NullPointerException", BuildFailureTelemetry.render(NullPointerException(), null).message)
    }

    @Test fun `truncates long messages on a UTF-8 character boundary`() {
        val report = BuildFailureTelemetry.render(RuntimeException("é".repeat(MAX_FAILURE_MESSAGE_BYTES)), null)
        assertTrue(report.truncated)
        assertTrue(report.message.toByteArray().size <= MAX_FAILURE_MESSAGE_BYTES)
        assertEquals(MAX_FAILURE_MESSAGE_BYTES / 2, report.message.length)
    }

    @Test fun `stops on cyclic causes`() {
        val first = RuntimeException("first")
        val second = RuntimeException("second", first)
        first.initCause(second)
        assertEquals("first\n> second", BuildFailureTelemetry.render(first, null).message)
    }

    @Test fun `reports a rethrown failure once and at most the per-build limit`() {
        val telemetry = BuildFailureTelemetry()
        val projectFailure = IllegalStateException("A problem occurred evaluating project ':app'.")
        assertNotNull(telemetry.report(projectFailure))
        assertNull(telemetry.report(RuntimeException("A problem occurred configuring project ':app'.", projectFailure)))
        assertNull(telemetry.report(null))
        repeat(MAX_FAILURE_REPORTS - 1) { assertNotNull(telemetry.report(RuntimeException("failure $it"))) }
        assertNull(telemetry.report(RuntimeException("one too many")))
    }
}
