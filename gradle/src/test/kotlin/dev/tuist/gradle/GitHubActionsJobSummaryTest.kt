package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GitHubActionsJobSummaryTest {
    @Test
    fun `background uploads finish summaries before returning across configuration cache reuse`(@TempDir projectDir: File) {
        val summary = File(projectDir, "summary.md").apply { writeText("Existing Gradle summary\n") }
        val server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path!!.endsWith("/gradle/builds") -> {
                    val report = Gson().fromJson(request.body.readUtf8(), BuildReportRequest::class.java)
                    MockResponse().setResponseCode(201).setBody("""{"id":"${report.id}"}""")
                        .setBodyDelay(2, TimeUnit.SECONDS)
                }
                request.path!!.endsWith("/tests") -> MockResponse().setBody("""{"id":"test-run"}""")
                    .setBodyDelay(2, TimeUnit.SECONDS)
                else -> MockResponse().setResponseCode(404)
            }
        }
        server.start()
        File(projectDir, "settings.gradle.kts").writeText("""
            plugins { id("dev.tuist") }
            tuist {
                project = "test-account/test-project"
                url = "${server.url("/")}"
                uploadInBackground = true
                network { proxy = false }
                buildCache { enabled = false }
                testQuarantine { enabled = false }
            }
            rootProject.name = "merchant"
        """.trimIndent())
        File(projectDir, "build.gradle.kts").writeText("""
            plugins { java }
            repositories { mavenCentral() }
            dependencies {
                testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
                testRuntimeOnly("org.junit.platform:junit-platform-launcher")
            }
            tasks.test { useJUnitPlatform() }
        """.trimIndent())
        File(projectDir, "src/test/java/MerchantTest.java").apply {
            parentFile.mkdirs()
            writeText("""
                import org.junit.jupiter.api.Test;
                import org.junit.jupiter.api.Disabled;
                public class MerchantTest {
                    @Test public void passes() {}
                    @Test public void fails() { throw new AssertionError("expected failure"); }
                    @Test @Disabled public void skipped() {}
                }
            """.trimIndent())
        }
        val runner = GradleRunner.create()
            .withProjectDir(projectDir)
            .withArguments("test", "--rerun-tasks", "--configuration-cache", "--max-workers=2")
            .withEnvironment(System.getenv() + mapOf(
                "TUIST_TOKEN" to "test-token",
                "TUIST_URL" to server.url("/").toString(),
                "TUIST_CACHE_ENDPOINT" to server.url("/").toString(),
                "CI" to "true",
                "GITHUB_ACTIONS" to "true",
                "GITHUB_STEP_SUMMARY" to summary.absolutePath
            ))
            .withPluginClasspath()
        try {
            val first = runner.buildAndFail()
            assertTrue(summary.readText().contains("### 🛠️ Tuist Build Report"), first.output + summary.readText())
            assertTrue(summary.readText().contains("### 🧪 Tuist Test Report"), first.output + summary.readText())
            val nextSummary = File(projectDir, "next-summary.md").apply { writeText("Other step summary\n") }
            val second = runner.withEnvironment(runner.environment!! + ("GITHUB_STEP_SUMMARY" to nextSummary.absolutePath))
                .buildAndFail()
            assertTrue(second.output.contains("Configuration cache entry reused"), second.output)
            assertTrue(summary.readText().startsWith("Existing Gradle summary\n"))
            assertEquals(1, Regex("### 🛠️ Tuist Build Report").findAll(summary.readText()).count())
            assertEquals(1, Regex("### 🧪 Tuist Test Report").findAll(summary.readText()).count())
            val markdown = nextSummary.readText()
            assertTrue(markdown.startsWith("Other step summary\n"))
            assertEquals(1, Regex("### 🛠️ Tuist Build Report").findAll(markdown).count(), second.output + markdown)
            assertEquals(1, Regex("### 🧪 Tuist Test Report").findAll(markdown).count())
            assertTrue(markdown.contains("| merchant | test | ❌ |"), markdown)
            assertTrue(markdown.contains("| merchant | ❌ | 3 | 1 | 1 |"), markdown)
            assertTrue(markdown.contains("${server.url("/")}test-account/test-project/builds/build-runs/"))
            assertTrue(markdown.contains("${server.url("/")}test-account/test-project/tests/test-runs/test-run"))

            val before = nextSummary.readText()
            runner.withEnvironment(runner.environment!! - "GITHUB_ACTIONS").buildAndFail()
            assertEquals(before, nextSummary.readText())
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `summary escapes cells and cannot fail a build on file errors`(@TempDir directory: File) {
        val report = buildReport(
            id = "build",
            taskOutcomes = listOf(TaskOutcome.LOCAL_HIT, TaskOutcome.REMOTE_HIT, TaskOutcome.EXECUTED).map { outcome ->
                TaskOutcomeData(":app:$outcome", outcome, true, 100, null, null, null)
            },
            buildFailed = false, totalDurationMs = 12_345,
            rootProjectName = "merchant|<app>\nrow", requestedTasks = listOf(":app:assemble"),
            ciDetector = object : CIDetector { override fun isCi() = true },
            gitInfoProvider = object : GitInfoProvider {
                override fun branch(): String? = null
                override fun commitSha(): String? = null
                override fun ref(): String? = null
                override fun remoteUrlOrigin(): String? = null
            }
        )
        val file = File(directory, "summary.md")
        val writer = GitHubActionsJobSummary(EnvironmentProvider { name ->
            mapOf("GITHUB_ACTIONS" to "true", "GITHUB_STEP_SUMMARY" to file.path)[name]
        })
        writer.writeBuild(report, "https://tuist.dev/build")
        assertTrue(file.readText().contains("merchant&#124;&lt;app&gt; row | :app:assemble | ✅ | 12.3s | 2 |"))

        GitHubActionsJobSummary(EnvironmentProvider { if (it == "GITHUB_ACTIONS") "true" else directory.path })
            .writeBuild(report, "https://tuist.dev/build")
        val missing = File(directory, "missing.md")
        GitHubActionsJobSummary(EnvironmentProvider { if (it == "GITHUB_ACTIONS") "false" else missing.path })
            .writeBuild(report, "https://tuist.dev/build")
        assertFalse(missing.exists())
        GitHubActionsJobSummary(EnvironmentProvider { if (it == "GITHUB_ACTIONS") "true" else null })
            .writeBuild(report, "https://tuist.dev/build")
    }
}
