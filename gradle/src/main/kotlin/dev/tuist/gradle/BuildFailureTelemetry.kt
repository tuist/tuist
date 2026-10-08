package dev.tuist.gradle

import org.gradle.api.tasks.VerificationException
import org.gradle.api.internal.tasks.execution.ExecuteTaskBuildOperationType
import org.gradle.configuration.project.ConfigureProjectBuildOperationType
import org.gradle.initialization.ConfigureBuildBuildOperationType
import org.gradle.initialization.EvaluateSettingsBuildOperationType

/** Retains a category, never exception messages or stack traces. */
internal class BuildFailureTelemetry {
    var buildFailed = false
        private set
    private var category: String? = null

    fun finished(details: Any?, failure: Throwable?) {
        if (failure == null) return
        val configuration = details is ConfigureBuildBuildOperationType.Details ||
            details is ConfigureProjectBuildOperationType.Details || details is EvaluateSettingsBuildOperationType.Details
        if (details !is ExecuteTaskBuildOperationType.Details && !configuration) return
        buildFailed = true
        val detected = if (configuration) "infrastructure_tooling" else classify(failure)
        // A failed dependency download can prevent tests or compilation from
        // running. Do not turn that into a source verification failure.
        if (detected == "infrastructure_tooling" || category == null) category = detected
    }

    fun metadata(metadata: BuildCustomMetadata): BuildCustomMetadata {
        val detected = category ?: return metadata
        if (metadata.values.size >= MAX_BUILD_METADATA_VALUES) return metadata
        return metadata.copy(values = metadata.values + ("tuist.detected_failure_category" to detected))
    }

    companion object {
        internal fun classify(failure: Throwable): String? {
            val seen = mutableSetOf<Throwable>()
            val causes = generateSequence(failure) { it.cause }.takeWhile { seen.add(it) }.take(32).toList()
            if (causes.any { it is java.io.IOException || it is OutOfMemoryError ||
                    it.javaClass.simpleName in setOf("ResolveException", "ArtifactResolveException", "ModuleVersionResolveException") }) {
                return "infrastructure_tooling"
            }
            if (causes.any { it is VerificationException ||
                    it.javaClass.simpleName in setOf("CompilationFailedException", "CompilationErrorException") }) {
                return "verification"
            }
            return null
        }
    }
}
