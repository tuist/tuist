package dev.tuist.gradle

internal fun interface EnvironmentProvider {
    fun getenv(name: String): String?
}

internal class SystemEnvironmentProvider : EnvironmentProvider {
    override fun getenv(name: String): String? = System.getenv(name)
}
