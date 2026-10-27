package dev.tuist.gradle

fun interface EnvironmentProvider {
    fun getenv(name: String): String?
}

class SystemEnvironmentProvider : EnvironmentProvider {
    override fun getenv(name: String): String? = System.getenv(name)
}
