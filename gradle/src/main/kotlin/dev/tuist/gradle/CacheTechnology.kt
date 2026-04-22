package dev.tuist.gradle

enum class CacheTechnology(val rawValue: String) {
    DEFAULT("default"),
    KURA("kura");

    val queryValue: String?
        get() = when (this) {
            DEFAULT -> null
            KURA -> rawValue
        }

    companion object {
        fun fromEnvironment(envProvider: (String) -> String? = { System.getenv(it) }): CacheTechnology {
            val value = envProvider("TUIST_KURA")
            return if (value.isNullOrBlank()) DEFAULT else KURA
        }
    }
}
