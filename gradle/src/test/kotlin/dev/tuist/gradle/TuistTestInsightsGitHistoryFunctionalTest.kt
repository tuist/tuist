package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Runs a pull request's tests through a real Gradle build in a real Git checkout on CI: the run
 * is reported with its place in the history, and the commits and branch heads follow it.
 */
class TuistTestInsightsGitHistoryFunctionalTest {

    @TempDir
    lateinit var tempDir: File

    private lateinit var server: MockWebServer
    private val requests = CopyOnWriteArrayList<Pair<String, String>>()
    private val fixture = GitRepositoryFixture()
    private val apiPath = "/api/projects/test-account/test-project/tests"

    private lateinit var projectDir: File
    private lateinit var forkPoint: String
    private lateinit var firstCommit: String
    private lateinit var feature: String
    private lateinit var mainHead: String

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                val body = request.body.readUtf8()
                requests += path to body
                return when {
                    path.contains("/api/cache/endpoints") ->
                        MockResponse().setResponseCode(200)
                            .setBody("""{"endpoints":["${server.url("/").toString().trimEnd('/')}"]}""")
                    path == apiPath && request.method == "POST" ->
                        MockResponse().setResponseCode(200).setBody("""{"id":"run-1","url":null}""")
                    path == "$apiPath/git-history/settings" ->
                        MockResponse().setResponseCode(200).setBody(
                            """{"window_days":365,"window_commits":5000,"deepen_budget_seconds":60,"upload_batch_size":500,"commit_file_limit":50000}"""
                        )
                    path == "$apiPath/git-history/commits/missing" -> {
                        val shas = JsonParser.parseString(body).asJsonObject.getAsJsonArray("shas")
                        MockResponse().setResponseCode(200).setBody(Gson().toJson(mapOf("missing" to shas.map { it.asString })))
                    }
                    path == "$apiPath/git-history/commits" -> MockResponse().setResponseCode(204)
                    path.startsWith("$apiPath/test-cases") ->
                        MockResponse().setResponseCode(200).setBody("""{"test_cases":[]}""")
                    else -> MockResponse().setResponseCode(200).setBody("{}")
                }
            }
        }
        server.start()

        val seed = fixture.init(File(tempDir, "seed"))
        firstCommit = fixture.commit(seed, "A1")
        forkPoint = fixture.commit(seed, "A2")
        fixture.git(seed, "checkout", "-q", "-b", "feature")
        feature = fixture.commit(seed, "F1")
        fixture.git(seed, "checkout", "-q", "main")
        mainHead = fixture.commit(seed, "M1")
        val origin = File(tempDir, "origin.git")
        fixture.git(tempDir, "clone", "-q", "--bare", seed.absolutePath, origin.absolutePath)
        projectDir = File(tempDir, "checkout")
        fixture.git(tempDir, "clone", "-q", "--branch", "feature", "file://${origin.absolutePath}", projectDir.absolutePath)
        writeProject()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `reports the run's Git history and uploads the commits after the run`() {
        val result = runner().build()

        val paths = requests.map { it.first }
        val runIndex = paths.indexOf(apiPath)
        assertTrue(runIndex >= 0, "the run was not reported:\n${result.output}")
        assertTrue(paths.indexOf("$apiPath/git-history/settings") in 0 until runIndex, paths.toString())
        assertTrue(paths.indexOf("$apiPath/git-history/commits/missing") > runIndex, paths.toString())

        val run = body(apiPath)
        assertEquals(feature, run.get("git_commit_sha").asString)
        assertEquals("client", run.get("history_source").asString)
        assertEquals("main", run.get("base_branch").asString)
        assertEquals(forkPoint, run.get("merge_base_sha").asString)
        assertEquals(true, run.get("is_pull_request").asBoolean)
        assertEquals(7, run.get("pull_request_number").asInt)
        assertEquals("sha1", run.get("git_object_format").asString)
        assertFalse(run.has("history_fallback_reason"), run.toString())

        val upload = body("$apiPath/git-history/commits")
        assertEquals(
            listOf(firstCommit, forkPoint, feature, mainHead),
            upload.getAsJsonArray("commits").map { it.asJsonObject.get("sha").asString }
        )
        assertEquals(
            listOf("feature" to feature, "main" to mainHead),
            upload.getAsJsonArray("branch_heads").map {
                it.asJsonObject.get("branch").asString to it.asJsonObject.get("sha").asString
            }
        )
    }

    @Test
    fun `collects no Git history when the upload is disabled`() {
        val result = runner("TUIST_GIT_UPLOAD_ENABLED" to "false").build()

        val paths = requests.map { it.first }
        assertTrue(paths.contains(apiPath), "the run was not reported:\n${result.output}")
        assertFalse(paths.any { it.contains("/git-history/") }, paths.toString())
        assertFalse(body(apiPath).has("history_source"))
    }

    private fun body(path: String): JsonObject =
        JsonParser.parseString(requests.last { it.first == path }.second).asJsonObject

    private fun runner(vararg environment: Pair<String, String>): GradleRunner =
        GradleRunner.create()
            .withProjectDir(projectDir)
            .withArguments("test", "--configuration-cache", "--stacktrace")
            .withPluginClasspath()
            .withEnvironment(
                System.getenv().filterKeys { key -> key !in ciEnvironmentVariables && !key.startsWith("TUIST_") } +
                    fixture.environment +
                    mapOf(
                        "CI" to "1",
                        "GITHUB_BASE_REF" to "main",
                        "GITHUB_REF" to "refs/pull/7/merge",
                        "TUIST_URL" to server.url("/").toString().trimEnd('/'),
                        "TUIST_TOKEN" to "test-token"
                    ) + environment
            )

    private fun writeProject() {
        File(projectDir, "settings.gradle.kts").writeText(
            """
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
            }

            rootProject.name = "git-history-fixture"
            """.trimIndent()
        )
        File(projectDir, "build.gradle.kts").writeText(
            """
            plugins {
                java
            }

            dependencies {
                testImplementation(files(${junitClasspath()}))
            }

            tasks.withType<Test>().configureEach {
                useJUnitPlatform()
            }
            """.trimIndent()
        )
        val testSource = File(projectDir, "src/test/java/dev/tuist/fixture/PassingTest.java")
        testSource.parentFile.mkdirs()
        testSource.writeText(
            """
            package dev.tuist.fixture;

            import org.junit.jupiter.api.Test;

            public class PassingTest {
                @Test
                public void passes() {
                }
            }
            """.trimIndent()
        )
    }

    private fun junitClasspath(): String =
        System.getProperty("java.class.path")
            .split(File.pathSeparator)
            .filter { it.contains("junit") || it.contains("opentest4j") || it.contains("apiguardian") }
            .joinToString(", ") { "\"${it.replace("\\", "\\\\")}\"" }

    private val ciEnvironmentVariables = setOf(
        "CI",
        "GITHUB_ACTIONS",
        "GITHUB_RUN_ID",
        "GITHUB_REF",
        "GITHUB_HEAD_REF",
        "GITHUB_BASE_REF",
        "GITLAB_CI",
        "CI_PIPELINE_ID",
        "CI_COMMIT_REF_NAME",
        "CI_MERGE_REQUEST_REF_PATH",
        "CI_MERGE_REQUEST_IID",
        "CI_MERGE_REQUEST_TARGET_BRANCH_NAME",
        "CIRCLECI",
        "CIRCLE_WORKFLOW_ID",
        "BUILDKITE",
        "BUILDKITE_BUILD_ID",
        "BUILDKITE_BRANCH",
        "BUILDKITE_PULL_REQUEST",
        "BUILDKITE_PULL_REQUEST_BASE_BRANCH",
        "CM_BUILD_ID",
        "BITRISE_IO"
    )
}
