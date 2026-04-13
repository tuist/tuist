package dev.tuist.gradle

import org.slf4j.LoggerFactory
import org.tomlj.Toml
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
            val proxy = result.getTable("proxy")?.let { table ->
                val proxyUrl = table.getString("url")
                val proxyEnv = table.getString("environment_variable")
                when {
                    !proxyUrl.isNullOrBlank() && !proxyEnv.isNullOrBlank() -> {
                        logger.warn(
                            "Tuist: {} has both `proxy.url` and `proxy.environment_variable` set — using `url` and ignoring `environment_variable`.",
                            file
                        )
                        TomlProxyConfig(url = proxyUrl)
                    }
                    !proxyUrl.isNullOrBlank() -> TomlProxyConfig(url = proxyUrl)
                    !proxyEnv.isNullOrBlank() -> TomlProxyConfig(environmentVariable = proxyEnv)
                    else -> null
                }
            }
            TomlConfig(
                project = result.getString("project"),
                url = result.getString("url"),
                proxy = proxy
            )
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to parse {}: {}", file, e.message)
            null
        }
    }
}
