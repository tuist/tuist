package dev.tuist.app.data.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FeatureFlagsHeadersTest {

    @Test
    fun `returns null when there are no feature flag environment variables`() {
        val headerValue = FeatureFlagsHeaders.headerValue(
            mapOf(
                "TUIST_TOKEN" to "token",
                "CI" to "true",
            )
        )

        assertNull(headerValue)
    }

    @Test
    fun `returns a comma separated list with only feature flag environment variables`() {
        val headerValue = FeatureFlagsHeaders.headerValue(
            mapOf(
                "TUIST_FEATURE_B" to "enabled",
                "TUIST_FEATURE_A" to "1",
                "TUIST_FEATURE_" to "ignored",
                "TUIST_TOKEN" to "token",
            )
        )

        assertEquals("A,B", headerValue)
    }
}
