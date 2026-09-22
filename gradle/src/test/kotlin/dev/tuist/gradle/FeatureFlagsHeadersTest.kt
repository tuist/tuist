package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FeatureFlagsHeadersTest {

    @Test
    fun `carries no flags when no variable is set`() {
        assertNull(FeatureFlagsHeaders.headerValue(emptyMap()))
    }

    @Test
    fun `carries no flags when no flag variable is set`() {
        assertNull(FeatureFlagsHeaders.headerValue(mapOf("TUIST_TOKEN" to "token")))
    }

    @ParameterizedTest
    @ValueSource(strings = ["0", "false", "FALSE", "no", "off", "", " 0 "])
    fun `a falsey value disables a flag`(value: String) {
        assertNull(FeatureFlagsHeaders.headerValue(mapOf("TUIST_FEATURE_FLAG_A" to value)))
    }

    @ParameterizedTest
    @ValueSource(strings = ["1", "true", "yes", "enabled"])
    fun `a truthy value enables a flag`(value: String) {
        assertEquals("A", FeatureFlagsHeaders.headerValue(mapOf("TUIST_FEATURE_FLAG_A" to value)))
    }

    @Test
    fun `a flag declared in lowercase is sent uppercased`() {
        assertEquals("COVERAGE", FeatureFlagsHeaders.headerValue(mapOf("TUIST_FEATURE_FLAG_coverage" to "1")))
    }

    @Test
    fun `encodes feature flags as a sorted comma separated list`() {
        val headerValue = FeatureFlagsHeaders.headerValue(
            mapOf(
                "TUIST_FEATURE_FLAG_B" to "1",
                "TUIST_FEATURE_FLAG_A" to "1"
            )
        )

        assertEquals("A,B", headerValue)
    }

    @Test
    fun `a falsey value disables only the flag it names`() {
        val headerValue = FeatureFlagsHeaders.headerValue(
            mapOf(
                "TUIST_FEATURE_FLAG_B" to "0",
                "TUIST_FEATURE_FLAG_A" to "1"
            )
        )

        assertEquals("A", headerValue)
    }

    @Test
    fun `ignores a variable that names no flag`() {
        assertNull(FeatureFlagsHeaders.headerValue(mapOf("TUIST_FEATURE_FLAG_" to "1")))
    }
}
