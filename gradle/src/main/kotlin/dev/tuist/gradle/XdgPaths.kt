package dev.tuist.gradle

import java.io.File

object XdgPaths {
    fun configHome(envProvider: (String) -> String? = { System.getenv(it) }): File {
        val path = envProvider("TUIST_XDG_CONFIG_HOME")?.takeIf { it.isNotBlank() }
            ?: envProvider("XDG_CONFIG_HOME")?.takeIf { it.isNotBlank() }
            ?: File(System.getProperty("user.home"), ".config").path
        return File(path)
    }

    fun stateHome(envProvider: (String) -> String? = { System.getenv(it) }): File {
        val path = envProvider("XDG_STATE_HOME")?.takeIf { it.isNotBlank() }
            ?: File(System.getProperty("user.home"), ".local/state").path
        return File(path)
    }
}
