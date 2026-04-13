package dev.tuist.gradle

import org.slf4j.LoggerFactory
import org.tomlj.Toml
import org.tomlj.TomlParseResult
import java.io.File

/**
 * Raw shape of the `[proxy]` table in `tuist.toml`.
 *
 * Exactly one of [url] or [environmentVariable] must be set — enforced by
 * [TomlParser] rather than the caller. `null` means the table was absent.
 */
data class TomlProxyConfig(
    val url: String? = null,
    val environmentVariable: String? = null
)

data class TomlConfig(
    val project: String?,
    val url: String?,
    val proxy: TomlProxyConfig? = null
)

object TomlParser {
    private val logger = LoggerFactory.getLogger(TomlParser::class.java)

    fun parse(file: File): TomlConfig? {
        if (!file.exists()) return null
        return try {
            val result = Toml.parse(file.toPath())
            if (result.hasErrors()) {
                result.errors().forEach { error ->
                    logger.warn("Tuist: Error parsing {}: {}", file, error.message)
                }
            }
            TomlConfig(
                project = result.getString("project"),
                url = result.getString("url"),
                proxy = parseProxyTable(result, file)
            )
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to parse {}: {}", file, e.message)
            null
        }
    }

    private fun parseProxyTable(result: TomlParseResult, file: File): TomlProxyConfig? {
        val table = result.getTable("proxy") ?: return null
        val url = table.getString("url")?.takeIf { it.isNotBlank() }
        val environmentVariable = table.getString("environment_variable")?.takeIf { it.isNotBlank() }

        if (url != null && environmentVariable != null) {
            logger.warn(
                "Tuist: {} has both `proxy.url` and `proxy.environment_variable` set — using `url` and ignoring `environment_variable`.",
                file
            )
            return TomlProxyConfig(url = url)
        }
        if (url != null) return TomlProxyConfig(url = url)
        if (environmentVariable != null) return TomlProxyConfig(environmentVariable = environmentVariable)
        return null
    }
}
