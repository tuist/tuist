package dev.tuist.gradle

import java.util.TreeSet

object FeatureFlagsHeaders {
    const val HEADER_NAME = "x-tuist-feature-flags"
    private const val ENVIRONMENT_PREFIX = "TUIST_FEATURE_FLAG_"

    /** Feature flags that are on unless a `TUIST_FEATURE_FLAG_<NAME>` variable turns them off. */
    private val DEFAULT_ENABLED = setOf("KURA")

    private val DISABLING_VALUES = setOf("", "0", "false", "no", "off")

    fun headerValue(environmentVariables: Map<String, String>): String? {
        val featureFlags = TreeSet(DEFAULT_ENABLED)

        environmentVariables.forEach { (name, value) ->
            val featureName = featureName(name) ?: return@forEach

            if (isEnabling(value)) {
                featureFlags.add(featureName)
            } else {
                featureFlags.remove(featureName)
            }
        }

        if (featureFlags.isEmpty()) return null

        return featureFlags.joinToString(",")
    }

    private fun featureName(variableName: String): String? {
        if (!variableName.startsWith(ENVIRONMENT_PREFIX)) return null

        val featureName = variableName.removePrefix(ENVIRONMENT_PREFIX)
        return if (featureName.isEmpty()) null else featureName.uppercase()
    }

    private fun isEnabling(value: String): Boolean = value.trim().lowercase() !in DISABLING_VALUES
}
