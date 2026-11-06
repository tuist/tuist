package dev.tuist.gradle

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class BuildCacheSavingsTelemetryTest {
    @Test fun `subtracts restoration time and clamps expensive restores to zero`() {
        val telemetry = BuildCacheSavingsTelemetry()
        telemetry.cachedTask(1000, 100)
        telemetry.cachedTask(200, 400)
        telemetry.cachedTask(0, 0)
        assertEquals("900", telemetry.metadata(BuildCustomMetadata()).values[BuildCacheSavingsTelemetry.KEY])
    }

    @Test fun `no cache hits reports a real zero`() {
        assertEquals("0", BuildCacheSavingsTelemetry().metadata(BuildCustomMetadata()).values[BuildCacheSavingsTelemetry.KEY])
    }

    @Test fun `missing timings incomplete telemetry and overflow never report partial totals`() {
        for (value in listOf(null, -1L, Long.MAX_VALUE)) {
            val telemetry = BuildCacheSavingsTelemetry()
            telemetry.cachedTask(100, 0)
            telemetry.cachedTask(value, 0)
            assertFalse(BuildCacheSavingsTelemetry.KEY in telemetry.metadata(BuildCustomMetadata()).values)
        }
        val telemetry = BuildCacheSavingsTelemetry()
        telemetry.markIncomplete()
        assertEquals(BuildCustomMetadata(), telemetry.metadata(BuildCustomMetadata()))
    }

    @Test fun `preserves metadata overrides and capacity`() {
        val telemetry = BuildCacheSavingsTelemetry()
        val explicit = BuildCustomMetadata(values = mapOf(BuildCacheSavingsTelemetry.KEY to "23"))
        assertEquals(explicit, telemetry.metadata(explicit))
        val full = BuildCustomMetadata(values = (1..MAX_BUILD_METADATA_VALUES).associate { "key$it" to "$it" })
        assertEquals(full, telemetry.metadata(full))
    }
}
