package dev.tuist.gradle

import org.slf4j.LoggerFactory
import org.tomlj.Toml
import java.io.File

data class TomlConfig(
    val project: String?,
    val url: String?
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
                url = result.getString("url")
            )
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to parse {}: {}", file, e.message)
            null
        }
    }
}
