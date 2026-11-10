package dev.tuist.gradle

import org.gradle.api.logging.Logging
import java.io.File
import java.util.Locale

internal class GitHubActionsJobSummary(
    environment: EnvironmentProvider = SystemEnvironmentProvider()
) {
    private val path = if (environment.getenv("GITHUB_ACTIONS") == "true") {
        environment.getenv("GITHUB_STEP_SUMMARY")?.takeIf { it.isNotBlank() }
    } else null

    val isEnabled: Boolean get() = path != null

    fun writeBuild(report: BuildReportRequest, url: String) {
        append("""
            ### 🛠️ Tuist Build Report

            | Project | Requested tasks | Status | Duration | Cache hits |
            | - | - | - | - | - |
            | ${cell(report.rootProjectName ?: "Unknown")} | ${cell(report.requestedTasks.joinToString(" "))} | ${status(report.status)} | ${String.format(Locale.ROOT, "%.1fs", report.durationMs / 1000.0)} | ${report.tasks.count { it.outcome == TaskOutcome.LOCAL_HIT || it.outcome == TaskOutcome.REMOTE_HIT }} |

            [View the full build report on Tuist]($url)
        """.trimIndent())
    }

    fun writeTests(report: TestReport, url: String) {
        val tests = report.testModules.flatMap { it.testCases }
        append("""
            ### 🧪 Tuist Test Report

            | Project | Status | Tests | Failed | Skipped |
            | - | - | - | - | - |
            | ${cell(report.scheme ?: "Unknown")} | ${status(report.status)} | ${tests.size} | ${tests.count { it.status == "failure" && !it.isQuarantined }} | ${tests.count { it.status == "skipped" }} |

            [View the full test report on Tuist]($url)
        """.trimIndent())
    }

    private fun append(markdown: String) {
        val path = path ?: return
        try {
            synchronized(GitHubActionsJobSummary::class.java) {
                File(path).appendText("\n$markdown\n", Charsets.UTF_8)
            }
        } catch (e: Exception) {
            Logging.getLogger(GitHubActionsJobSummary::class.java)
                .debug("Tuist: Failed to write the GitHub Actions job summary: ${e.message}")
        }
    }

    private fun cell(value: String): String = value.replace("&", "&amp;")
        .replace("<", "&lt;").replace(">", "&gt;").replace("|", "&#124;")
        .replace("\r", " ").replace("\n", " ")

    private fun status(value: String): String = if (value == "success") "✅" else "❌"
}
