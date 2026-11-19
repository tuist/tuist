package dev.tuist.gradle

import org.gradle.api.tasks.VerificationException
import org.gradle.api.internal.tasks.execution.ExecuteTaskBuildOperationType
import org.gradle.configuration.project.ConfigureProjectBuildOperationType
import org.gradle.initialization.ConfigureBuildBuildOperationType
import org.gradle.initialization.EvaluateSettingsBuildOperationType
import org.gradle.internal.exceptions.MultiCauseException
import java.util.Collections
import java.util.IdentityHashMap

/** The message and cause chain of a failed task or configuration operation, never a stack trace. */
data class FailureReport(val message: String, val truncated: Boolean)

internal const val MAX_FAILURE_REPORTS = 32
internal const val MAX_FAILURE_MESSAGE_BYTES = 16 * 1024
private const val MAX_FAILURE_CAUSES = 16

/**
 * Classifies the build failure into a normalized category, and renders bounded
 * failure messages for the operations that failed.
 */
internal class BuildFailureTelemetry(private val rootDir: String? = null) {
    var buildFailed = false
        private set
    private var category: String? = null
    private var reported = 0
    private val reportedFailures = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())

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

    /**
     * Reports at most [MAX_FAILURE_REPORTS] failures per build. A failure that an
     * enclosing operation rethrows (a project failure failing its build) is reported once,
     * by the operation that finished first.
     */
    fun report(failure: Throwable?): FailureReport? {
        if (failure == null || reported >= MAX_FAILURE_REPORTS) return null
        val chain = causes(failure)
        if (chain.any { it in reportedFailures }) return null
        reportedFailures.addAll(chain)
        reported++
        return render(failure, rootDir)
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

        /**
         * Renders the failure the way Gradle's console does: the message, then each cause
         * on a `>` line, indented by depth. Paths inside the root project become relative.
         */
        internal fun render(failure: Throwable, rootDir: String?): FailureReport {
            val text = StringBuilder()
            val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
            fun visit(throwable: Throwable, depth: Int, parentMessage: String?) {
                if (seen.size >= MAX_FAILURE_CAUSES || !seen.add(throwable) || text.length > MAX_FAILURE_MESSAGE_BYTES) return
                val message = (throwable.message?.takeIf { it.isNotBlank() } ?: throwable.javaClass.name)
                    .take(MAX_FAILURE_MESSAGE_BYTES + 1)
                if (message != parentMessage) {
                    val indent = "  ".repeat(depth)
                    message.trimEnd().lines().forEachIndexed { index, line ->
                        if (text.isNotEmpty()) text.append('\n')
                        when {
                            depth == 0 -> text.append(line)
                            index == 0 -> text.append("  ".repeat(depth - 1)).append("> ").append(line)
                            else -> text.append(indent).append(line)
                        }
                    }
                }
                val next = if (message != parentMessage) depth + 1 else depth
                children(throwable).forEach { visit(it, next, message) }
            }
            visit(failure, 0, null)
            return truncateUtf8(relativize(text.toString(), rootDir), MAX_FAILURE_MESSAGE_BYTES)
        }

        private fun children(throwable: Throwable): List<Throwable> = try {
            if (throwable is MultiCauseException) throwable.causes else listOfNotNull(throwable.cause)
        } catch (_: LinkageError) {
            listOfNotNull(throwable.cause)
        }

        private fun causes(failure: Throwable): Set<Throwable> {
            val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
            val pending = ArrayDeque(listOf(failure))
            while (pending.isNotEmpty() && seen.size < MAX_FAILURE_CAUSES) {
                val next = pending.removeFirst()
                if (seen.add(next)) pending.addAll(children(next))
            }
            return seen
        }

        /** Replaces the root project directory, including `file:` URLs, with relative paths. */
        internal fun relativize(text: String, rootDir: String?): String {
            val root = rootDir?.trimEnd('/', '\\')?.takeIf { it.isNotEmpty() } ?: return text
            val prefix = "(?:file:(?://)?)?" + Regex.escape(root)
            return text
                .replace(Regex("$prefix[/\\\\]"), "")
                .replace(Regex("$prefix(?![\\w.-])"), ".")
        }

        internal fun truncateUtf8(text: String, maxBytes: Int): FailureReport {
            val bytes = text.toByteArray(Charsets.UTF_8)
            if (bytes.size <= maxBytes) return FailureReport(text, truncated = false)
            var end = maxBytes
            // Never split a multi-byte character: back up to the start of the one cut off.
            while (end > 0 && (bytes[end].toInt() and 0xC0) == 0x80) end--
            return FailureReport(String(bytes, 0, end, Charsets.UTF_8), truncated = true)
        }
    }
}
