package dev.tuist.gradle

import org.gradle.api.internal.tasks.execution.ExecuteTaskBuildOperationType
import org.gradle.api.tasks.VerificationException
import org.gradle.configuration.project.ConfigureProjectBuildOperationType
import org.junit.jupiter.api.Test
import java.io.IOException
import java.lang.reflect.Proxy
import kotlin.test.assertEquals
import kotlin.test.assertFalse
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

    @Test fun `infrastructure failure wins over verification and no diagnostics are uploaded`() {
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
}
