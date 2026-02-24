package dev.tuist.gradle

interface CIDetector {
    fun isCi(): Boolean
}

class EnvironmentCIDetector : CIDetector {
    override fun isCi(): Boolean = System.getenv("CI") != null
}
