package dev.tuist.gradle

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

private class StaticBuildSystemMetadataProvider(
    private val metadata: Map<String, String>
) : BuildSystemMetadataProvider {
    override fun values(isCi: Boolean): Map<String, String> = metadata
}

private class StaticGitInfoProvider(private val dirty: Boolean?) : GitInfoProvider {
    override fun branch(): String? = null
    override fun commitSha(): String? = null
    override fun ref(): String? = null
    override fun remoteUrlOrigin(): String? = null
    override fun isDirty(): Boolean? = dirty
}

private class StaticCIDetector(private val ci: Boolean) : CIDetector {
    override fun isCi(): Boolean = ci
}

class BuildCustomMetadataTest {
    @Test
    fun `combines default, environment, and configured metadata`() {
        val metadata = buildCustomMetadata(
            environment = mapOf(
                "TUIST_BUILD_TAGS" to "nightly, android",
                "TUIST_BUILD_VALUE_TICKET" to "TUIST-123",
                "TUIST_BUILD_VALUE_CPU_MODEL" to "Custom processor"
            ),
            configuredTags = listOf("android", "release"),
            configuredValues = mapOf("ticket" to "TUIST-456", "team" to "mobile"),
            systemMetadataProvider =
                StaticBuildSystemMetadataProvider(
                    mapOf(
                        "cpu_model" to "Default processor",
                        "memory_total_bytes" to "17179869184",
                        "power_source" to "ac"
                    )
                )
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
            configuredTags = listOf("", " release "),
            systemMetadataProvider = StaticBuildSystemMetadataProvider(emptyMap())
        )

        assertEquals(listOf("nightly", "release"), metadata.tags)
    }

    @Test
    fun `prefers a Linux processor model name to processor index`() {
        assertEquals(
            "AMD EPYC 7B12",
            parseLinuxCpuModel(
                sequenceOf(
                    "processor : 0",
                    "model name : AMD EPYC 7B12",
                    "model : 1"
                )
            )
        )
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
            ),
            systemMetadataProvider = StaticBuildSystemMetadataProvider(emptyMap())
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
    fun `keeps configured values when metadata sources exceed the shared limit`() {
        val metadata = buildCustomMetadata(
            environment = (1..MAX_BUILD_METADATA_VALUES).associate { "TUIST_BUILD_VALUE_ENV_$it" to "environment-$it" },
            configuredValues = (1..MAX_BUILD_METADATA_VALUES).associate { "configured-$it" to "value-$it" },
            systemMetadataProvider = StaticBuildSystemMetadataProvider(mapOf("cpu_model" to "processor"))
        )

        assertEquals(MAX_BUILD_METADATA_VALUES, metadata.values.size)
        assertEquals("value-1", metadata.values["configured-1"])
        assertFalse(metadata.values.containsKey("env_1"))
        assertFalse(metadata.values.containsKey("cpu_model"))
    }

    @Test
    fun `keeps explicit metadata independent of system probes`() {
        val metadata = buildCustomMetadata(
            environment = mapOf("TUIST_BUILD_TAGS" to "nightly", "TUIST_BUILD_VALUE_TEAM" to "android"),
            configuredTags = listOf("release"),
            configuredValues = mapOf("workflow" to "deploy"),
            systemMetadataProvider = StaticBuildSystemMetadataProvider(mapOf("cpu_model" to "processor"))
        )

        assertEquals(listOf("nightly", "release"), metadata.tags)
        assertEquals(mapOf("workflow" to "deploy", "team" to "android"), metadata.values)
    }

}
