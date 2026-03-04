package dev.tuist.gradle

import org.tomlj.Toml
import java.io.File

data class TomlConfig(val project: String?, val url: String?)

object TomlParser {
    fun parse(file: File): TomlConfig? {
        if (!file.exists()) return null
        return try {
            val result = Toml.parse(file.toPath())
            TomlConfig(
                project = result.getString("project"),
                url = result.getString("url")
            )
        } catch (_: Exception) {
            null
        }
    }
}
