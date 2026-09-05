package dev.tuist.gradle

import java.util.Locale

data class BuildCustomMetadata(
    val tags: List<String> = emptyList(),
    val values: Map<String, String> = emptyMap()
)

internal const val MAX_BUILD_METADATA_TAGS = 50
internal const val MAX_BUILD_METADATA_TAG_LENGTH = 50
internal const val MAX_BUILD_METADATA_VALUES = 20
internal const val MAX_BUILD_METADATA_KEY_LENGTH = 50
internal const val MAX_BUILD_METADATA_VALUE_LENGTH = 500

private val validBuildMetadataTag = Regex("^[a-zA-Z0-9_-]+$")

internal fun buildCustomMetadata(
    environment: Map<String, String> = System.getenv(),
    configuredTags: Iterable<String> = emptyList(),
    configuredValues: Map<String, String> = emptyMap()
): BuildCustomMetadata {
    val environmentTags =
        environment["TUIST_BUILD_TAGS"]
            ?.split(',')
            .orEmpty()
            .map(String::trim)
            .filter(String::isNotEmpty)

    val environmentValues =
        environment
            .filterKeys { it.startsWith("TUIST_BUILD_VALUE_") }
            .mapKeys { (key, _) -> key.removePrefix("TUIST_BUILD_VALUE_").lowercase(Locale.ROOT) }

    return BuildCustomMetadata(
        tags = normalizeBuildMetadataTags(environmentTags + configuredTags),
        values =
            mergeBuildMetadataValues(
                configuredValues,
                environmentValues
            )
    )
}

private fun normalizeBuildMetadataTags(tags: Iterable<String>): List<String> =
    tags
        .asSequence()
        .map(String::trim)
        .filter(String::isNotEmpty)
        .filter { it.length <= MAX_BUILD_METADATA_TAG_LENGTH && validBuildMetadataTag.matches(it) }
        .distinct()
        .take(MAX_BUILD_METADATA_TAGS)
        .toList()

private fun normalizeBuildMetadataValues(values: Map<String, String>): Map<String, String> =
    values.filter { (key, value) ->
        key.isNotBlank() &&
            key.length <= MAX_BUILD_METADATA_KEY_LENGTH &&
            value.length <= MAX_BUILD_METADATA_VALUE_LENGTH
    }

private fun mergeBuildMetadataValues(vararg sources: Map<String, String>): Map<String, String> =
    buildMap {
        sources.forEach { source ->
            normalizeBuildMetadataValues(source).forEach { (key, value) -> putIfAbsent(key, value) }
        }
    }.entries.take(MAX_BUILD_METADATA_VALUES).associate { it.toPair() }
