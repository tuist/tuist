package dev.tuist.gradle

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class BuildCustomMetadataTest {
    @Test
    fun `combines environment and configured metadata`() {
        val metadata = buildCustomMetadata(
            environment = mapOf(
                "TUIST_BUILD_TAGS" to "nightly, android",
                "TUIST_BUILD_VALUE_TICKET" to "TUIST-123",
                "TUIST_BUILD_VALUE_CPU_MODEL" to "Custom processor"
            ),
            configuredTags = listOf("android", "release"),
            configuredValues = mapOf("ticket" to "TUIST-456", "team" to "mobile")
        )

        assertEquals(listOf("nightly", "android", "release"), metadata.tags)
        assertEquals(
            mapOf(
                "cpu_model" to "Custom processor",
                "ticket" to "TUIST-456",
                "team" to "mobile"
            ),
            metadata.values
        )
    }

    @Test
    fun `removes blank tags`() {
        val metadata = buildCustomMetadata(
            environment = mapOf("TUIST_BUILD_TAGS" to " nightly, ,"),
            configuredTags = listOf("", " release ")
        )

        assertEquals(listOf("nightly", "release"), metadata.tags)
    }

    @Test
    fun `filters invalid metadata without dropping valid metadata`() {
        val metadata = buildCustomMetadata(
            environment = mapOf(
                "TUIST_BUILD_TAGS" to "environment,not/a-tag",
                "TUIST_BUILD_VALUE_TICKET" to "TUIST-123"
            ),
            configuredTags = List(MAX_BUILD_METADATA_TAGS + 1) { "tag-$it" } + listOf("spaces are invalid"),
            configuredValues = mapOf(
                "ticket" to "x".repeat(MAX_BUILD_METADATA_VALUE_LENGTH + 1),
                "x".repeat(MAX_BUILD_METADATA_KEY_LENGTH + 1) to "ignored",
                "valid" to "value",
                "" to "ignored"
            )
        )

        assertEquals(MAX_BUILD_METADATA_TAGS, metadata.tags.size)
        assertEquals("environment", metadata.tags.first())
        assertFalse(metadata.tags.any { '/' in it || ' ' in it })
        assertEquals("TUIST-123", metadata.values["ticket"])
        assertEquals("value", metadata.values["valid"])
        assertFalse(metadata.values.containsKey(""))
        assertFalse(metadata.values.keys.any { it.length > MAX_BUILD_METADATA_KEY_LENGTH })
    }

    @Test
    fun `prioritizes configured values when user metadata exceeds the shared limit`() {
        val metadata = buildCustomMetadata(
            environment = (1..MAX_BUILD_METADATA_VALUES).associate { "TUIST_BUILD_VALUE_ENV_$it" to "environment-$it" },
            configuredValues = (1..MAX_BUILD_METADATA_VALUES).associate { "configured-$it" to "value-$it" }
        )

        assertEquals(MAX_BUILD_METADATA_VALUES, metadata.values.size)
        assertEquals("value-1", metadata.values["configured-1"])
        assertFalse(metadata.values.containsKey("env_1"))
    }

    @Test
    fun `merges environment and configured metadata`() {
        val metadata = buildCustomMetadata(
            environment = mapOf("TUIST_BUILD_TAGS" to "nightly", "TUIST_BUILD_VALUE_TEAM" to "android"),
            configuredTags = listOf("release"),
            configuredValues = mapOf("workflow" to "deploy")
        )

        assertEquals(listOf("nightly", "release"), metadata.tags)
        assertEquals(mapOf("workflow" to "deploy", "team" to "android"), metadata.values)
    }

}
