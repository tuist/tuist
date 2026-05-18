package dev.tuist.gradle

import java.util.TreeSet

object FeatureFlagsHeaders {
    const val HEADER_NAME = "x-tuist-feature-flags"
    private const val ENVIRONMENT_PREFIX = "TUIST_FEATURE_FLAG_"

    fun headerValue(environmentVariables: Map<String, String>): String? {
        val featureFlags = TreeSet<String>()

        environmentVariables.forEach { (name, _) ->
            val featureName = name.removePrefix(ENVIRONMENT_PREFIX)
            if (name.startsWith(ENVIRONMENT_PREFIX) && featureName.isNotEmpty()) {
                featureFlags.add(featureName)
            }
        }

        if (featureFlags.isEmpty()) return null

        return featureFlags.joinToString(",")
    }
}
