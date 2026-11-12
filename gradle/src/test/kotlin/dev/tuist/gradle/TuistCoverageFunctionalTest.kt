package dev.tuist.gradle

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.BuildResult
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Runs a two-project Java build with coverage on, through real Gradle builds in a real Git
 * checkout, with the configuration cache: what each kind of run reports as its coverage, its
 * test-scoped evidence and what it left out.
 */
class TuistCoverageFunctionalTest {

    @TempDir
    lateinit var tempDir: File

    private lateinit var server: MockWebServer
    private val requests = CopyOnWriteArrayList<Pair<String, String>>()
    private val fixture = GitRepositoryFixture()
    private val apiPath = "/api/projects/test-account/test-project/tests"
    private lateinit var projectDir: File

    @Volatile
    private var quarantined = "[]"

    @Volatile
    private var shardPlanId = "00000000-0000-0000-0000-000000000001"

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                requests += path to request.body.readUtf8()
                return when {
                    path.contains("/api/cache/endpoints") ->
                        MockResponse().setResponseCode(200)
                            .setBody("""{"endpoints":["${server.url("/").toString().trimEnd('/')}"]}""")
                    path == apiPath && request.method == "POST" ->
                        MockResponse().setResponseCode(200).setBody("""{"id":"run-1","url":null}""")
                    path == "$apiPath/coverage/settings" ->
                        MockResponse().setResponseCode(200).setBody("""{"inline_threshold_bytes":5000000}""")
                    path == "$apiPath/git-history/settings" ->
                        MockResponse().setResponseCode(200).setBody(
                            """{"window_days":365,"window_commits":5000,"deepen_budget_seconds":5,"upload_batch_size":500,"commit_file_limit":50000}"""
                        )
                    path == "$apiPath/git-history/commits/missing" || path == "$apiPath/git-history/listings/missing" -> {
                        val shas = JsonParser.parseString(requests.last().second).asJsonObject.getAsJsonArray("shas")
                        MockResponse().setResponseCode(200).setBody("""{"missing":$shas}""")
                    }
                    path.startsWith("$apiPath/git-history/") -> MockResponse().setResponseCode(204)
                    path.startsWith("$apiPath/coverage/commits/") ->
                        MockResponse().setResponseCode(200).setBody("""{"coverage":"82.5"}""")
                    // A catch-all shard: it runs every test task without a filter.
                    path.startsWith("$apiPath/shards/") ->
                        MockResponse().setResponseCode(200).setBody(
                            """{"download_urls":[],"modules":[],"shard_plan_id":"$shardPlanId","suites":{},"skip":[]}"""
                        )
                    path.startsWith("$apiPath/test-cases") ->
                        MockResponse().setResponseCode(200).setBody("""{"test_cases":$quarantined}""")
                    else -> MockResponse().setResponseCode(200).setBody("{}")
                }
            }
        }
        server.start()
        projectDir = fixture.init(File(tempDir, "checkout"))
        writeProject()
        fixture.git(projectDir, "remote", "add", "origin", "https://github.com/tuist/coverage-fixture.git")
        fixture.git(projectDir, "add", ".")
        fixture.git(projectDir, "commit", "-q", "-m", "Fixture")
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `a full run reports its coverage and each test's evidence`() {
        val result = runner("test").build()
        val run = run(result)

        assertEquals(true, run.get("coverage_enabled").asBoolean)
        assertEquals(false, run.get("git_dirty").asBoolean)
        assertFalse(run.has("only_test_identifiers"), run.toString())
        assertFalse(run.has("skip_test_identifiers"), run.toString())

        val coverage = run.getAsJsonObject("coverage")
        assertEquals("jacoco", coverage.get("tool").asString)
        assertEquals(false, coverage.get("partial").asBoolean, result.output)

        val calc = file(coverage, "core/src/main/java/dev/tuist/fixture/Calc.java")
        assertEquals(listOf(":core"), calc.getAsJsonArray("targets").map { it.asString })
        assertEquals(false, calc.get("is_test").asBoolean)
        assertEquals(blob("core/src/main/java/dev/tuist/fixture/Calc.java"), calc.get("git_blob_id").asString)
        val lines = lineCounts(calc)
        // `add`, `multiply` and `warmUp` ran; `unused` never did.
        assertEquals(1, lines[line("Calc.java", "return a + b")])
        assertEquals(1, lines[line("Calc.java", "return a * b")])
        assertEquals(0, lines[line("Calc.java", "return -a")])
        assertTrue(calc.getAsJsonArray("functions").any { it.asJsonObject.get("name").asString == "Calc.add(int, int)" })

        val greeter = file(coverage, "app/src/main/java/dev/tuist/fixture/app/Greeter.java")
        assertEquals(listOf(":app"), greeter.getAsJsonArray("targets").map { it.asString })

        val test = file(coverage, "core/src/test/java/dev/tuist/fixture/CalcTest.java")
        assertEquals(true, test.get("is_test").asBoolean)
        assertEquals(0, test.getAsJsonArray("line_numbers").size())

        val evidence = run.getAsJsonObject("coverage_evidence")
        assertEquals("collected", evidence.get("status").asString)
        val calcPath = "core/src/main/java/dev/tuist/fixture/Calc.java"
        // Each test has the lines it ran itself; what the class's @BeforeAll ran is its suite's.
        assertEquals(
            listOf(line("Calc.java", "return a + b")).flatMap { listOf(it, it) },
            scopeLines(evidence, "test", ":core", "dev.tuist.fixture.CalcTest", "adds()", calcPath)
        )
        assertFalse(line("Calc.java", "return a * b") in expand(scopeLines(evidence, "test", ":core", "dev.tuist.fixture.CalcTest", "adds()", calcPath)))
        assertTrue(line("Calc.java", "return a * b") in expand(scopeLines(evidence, "test", ":core", "dev.tuist.fixture.CalcTest", "multiplies()", calcPath)))
        assertTrue(line("Calc.java", "warmed = true") in expand(scopeLines(evidence, "suite", ":core", "dev.tuist.fixture.CalcTest", "", calcPath)))
        assertFalse(line("Calc.java", "warmed = true") in expand(scopeLines(evidence, "test", ":core", "dev.tuist.fixture.CalcTest", "adds()", calcPath)))
        // The app's test runs core's code through it, and its target holds everything its JVM ran.
        assertTrue(calcPath in scopePaths(evidence, "test", ":app", "dev.tuist.fixture.app.GreeterTest", "greets()"))
        assertTrue(calcPath in scopePaths(evidence, "target", ":core", "", ""))
        assertEquals(0, evidence.getAsJsonArray("overlapped_tests").size())

        // A clean checkout's listing follows the run.
        val paths = requests.map { it.first }
        assertTrue(paths.indexOf("$apiPath/git-history/listings") > paths.indexOf(apiPath), paths.toString())
        val listing = body("$apiPath/git-history/listings")
        assertTrue(listing.getAsJsonArray("files").any { it.asJsonObject.get("path").asString == calcPath })
    }

    @Test
    fun `test tasks restored from the build cache, or up to date, report the coverage of the run that executed them`() {
        runner("test", "--build-cache").build()
        val executed = run()
        val executedLines = lineCounts(file(executed.getAsJsonObject("coverage"), "core/src/main/java/dev/tuist/fixture/Calc.java"))

        // Up to date: no test runs, and the configuration cache is reused.
        val upToDate = runner("test", "--build-cache").build()
        assertEquals(TaskOutcome.UP_TO_DATE, upToDate.task(":core:test")?.outcome)
        assertTrue(upToDate.output.contains("Reusing configuration cache"), upToDate.output)
        val restored = run(upToDate)
        assertEquals(0, restored.getAsJsonArray("test_modules").size())
        assertEquals(false, restored.getAsJsonObject("coverage").get("partial").asBoolean)
        assertEquals(executedLines, lineCounts(file(restored.getAsJsonObject("coverage"), "core/src/main/java/dev/tuist/fixture/Calc.java")))
        // Its evidence is the run's that executed the tests, which reported it.
        assertFalse(restored.has("coverage_evidence"), restored.toString())

        // From the build cache, after the outputs are gone.
        File(projectDir, "core/build").deleteRecursively()
        File(projectDir, "app/build").deleteRecursively()
        val fromCache = runner("test", "--build-cache").build()
        assertEquals(TaskOutcome.FROM_CACHE, fromCache.task(":core:test")?.outcome)
        val cached = run(fromCache)
        assertEquals(false, cached.getAsJsonObject("coverage").get("partial").asBoolean)
        assertEquals(executedLines, lineCounts(file(cached.getAsJsonObject("coverage"), "core/src/main/java/dev/tuist/fixture/Calc.java")))
    }

    @Test
    fun `a shard retried with nothing to run reports once per plan`() {
        val shard = mapOf("TUIST_SHARD_INDEX" to "0", "TUIST_SHARD_REFERENCE" to "reference")
        val reports = { requests.count { it.first == apiPath } }

        val first = runner("test", environment = shard).build()
        assertEquals(TaskOutcome.SUCCESS, first.task(":core:test")?.outcome, first.output)
        assertEquals(1, reports())
        assertEquals(shardPlanId, run(first).get("shard_plan_id").asString)

        // The same shard again: its tests are up to date, so it ran nothing new and stays reported once.
        val retry = runner("test", environment = shard).build()
        assertEquals(TaskOutcome.UP_TO_DATE, retry.task(":core:test")?.outcome, retry.output)
        assertEquals(1, reports(), retry.output)

        // The same shard of another plan, up to date as well, reports its restored coverage.
        shardPlanId = "00000000-0000-0000-0000-000000000002"
        val nextPlan = runner("test", environment = shard).build()
        assertEquals(TaskOutcome.UP_TO_DATE, nextPlan.task(":core:test")?.outcome, nextPlan.output)
        assertEquals(2, reports(), nextPlan.output)
        val restored = run(nextPlan)
        assertEquals(shardPlanId, restored.get("shard_plan_id").asString)
        assertEquals(false, restored.getAsJsonObject("coverage").get("partial").asBoolean, nextPlan.output)
    }

    @Test
    fun `a run its caller narrowed with --tests names the tests it ran`() {
        val result = runner(":core:test", "--tests", "dev.tuist.fixture.CalcTest.adds").build()
        val run = run(result)

        assertEquals(true, run.getAsJsonObject("coverage").get("partial").asBoolean)
        assertEquals(listOf(":core/dev.tuist.fixture.CalcTest/adds()"), run.getAsJsonArray("only_test_identifiers").map { it.asString })
        assertFalse(run.has("skip_test_identifiers"), run.toString())
    }

    @Test
    fun `a run of some projects' tests names the projects it ran`() {
        val run = run(runner(":core:test").build())

        assertEquals(true, run.getAsJsonObject("coverage").get("partial").asBoolean)
        assertEquals(listOf(":core"), run.getAsJsonArray("only_test_identifiers").map { it.asString })
    }

    @Test
    fun `a run that excludes a project's tests names the project it skipped`() {
        val run = run(runner("test", "-x", ":app:test").build())

        assertEquals(true, run.getAsJsonObject("coverage").get("partial").asBoolean)
        assertEquals(listOf(":app"), run.getAsJsonArray("skip_test_identifiers").map { it.asString })
        assertFalse(run.has("only_test_identifiers"), run.toString())
    }

    @Test
    fun `quarantined tests leave the run full`() {
        quarantined = """[{"name":"multiplies","module":{"id":"1","name":":core"},"suite":{"id":"2","name":"dev.tuist.fixture.CalcTest"},"state":"skipped"}]"""

        val run = run(runner("test").build())

        assertEquals(false, run.getAsJsonObject("coverage").get("partial").asBoolean)
        assertFalse(run.has("skip_test_identifiers"), run.toString())
        assertFalse(run.has("only_test_identifiers"), run.toString())
        val calc = lineCounts(file(run.getAsJsonObject("coverage"), "core/src/main/java/dev/tuist/fixture/Calc.java"))
        // Only the quarantined test ran it, so it counts as uncovered.
        assertEquals(0, calc[line("Calc.java", "return a * b")])
    }

    @Test
    fun `a run with coverage off says so and reports none`() {
        writeProject(coverage = false)

        val result = runner("test").build()
        val run = run(result)

        assertEquals(false, run.get("coverage_enabled").asBoolean)
        assertFalse(run.has("coverage"), run.toString())
        assertFalse(run.has("coverage_evidence"), run.toString())
        assertFalse(File(projectDir, "core/build/jacoco").exists())
        assertFalse(requests.any { it.first.contains("/git-history/listings") })
    }

    @Test
    fun `the environment turns coverage on for a build that does not`() {
        writeProject(coverage = false)

        val run = run(runner("test", environment = mapOf("TUIST_TEST_COVERAGE" to "1")).build())

        assertEquals(true, run.get("coverage_enabled").asBoolean)
        assertNotNull(run.getAsJsonObject("coverage"))
    }

    @Test
    fun `a dirty checkout reports its coverage as dirty and uploads no listing`() {
        File(projectDir, "core/src/main/java/dev/tuist/fixture/Calc.java").appendText("\n")

        val run = run(runner("test").build())

        assertEquals(true, run.get("git_dirty").asBoolean)
        assertNull(requests.firstOrNull { it.first == "$apiPath/git-history/listings" })
    }

    @Test
    fun `tests JUnit runs at the same time in one JVM are reported as overlapped, with their target's evidence`() {
        write(
            "core/build.gradle.kts",
            File(projectDir, "core/build.gradle.kts").readText() + """

            tasks.withType<Test>().configureEach {
                systemProperty("junit.jupiter.execution.parallel.enabled", "true")
                systemProperty("junit.jupiter.execution.parallel.mode.default", "concurrent")
                systemProperty("junit.jupiter.execution.parallel.config.strategy", "fixed")
                systemProperty("junit.jupiter.execution.parallel.config.fixed.parallelism", "2")
            }
            """.trimIndent()
        )
        write(
            "core/src/test/java/dev/tuist/fixture/CalcTest.java",
            """
            package dev.tuist.fixture;

            import static org.junit.jupiter.api.Assertions.assertEquals;

            import java.util.concurrent.CyclicBarrier;
            import java.util.concurrent.TimeUnit;
            import org.junit.jupiter.api.Test;

            public class CalcTest {
                // Both tests wait for each other, so they surely run at the same time.
                private static final CyclicBarrier BOTH = new CyclicBarrier(2);

                @Test
                void adds() throws Exception {
                    BOTH.await(30, TimeUnit.SECONDS);
                    assertEquals(3, Calc.add(1, 2));
                }

                @Test
                void multiplies() throws Exception {
                    BOTH.await(30, TimeUnit.SECONDS);
                    assertEquals(6, Calc.multiply(2, 3));
                }
            }
            """.trimIndent()
        )

        val run = run(runner(":core:test").build())
        val evidence = run.getAsJsonObject("coverage_evidence")

        assertEquals(
            setOf("adds()", "multiplies()"),
            evidence.getAsJsonArray("overlapped_tests").map { it.asJsonObject }
                .filter { it.get("suite").asString == "dev.tuist.fixture.CalcTest" }
                .map { it.get("name").asString }.toSet()
        )
        assertFalse(evidence.getAsJsonArray("scopes").any { it.asJsonObject.get("kind").asString == "test" })
        val target = scopePaths(evidence, "target", ":core", "", "")
        assertTrue("core/src/main/java/dev/tuist/fixture/Calc.java" in target, target.toString())
        // What the overlapped tests ran is still measured.
        val calc = lineCounts(file(run.getAsJsonObject("coverage"), "core/src/main/java/dev/tuist/fixture/Calc.java"))
        assertEquals(1, calc[line("Calc.java", "return a * b")])
    }

    @Test
    fun `tuistCoverageComplete signals the checkout's commit complete`() {
        val head = fixture.git(projectDir, "rev-parse", "HEAD")

        val result = runner("tuistCoverageComplete").build()

        assertTrue(requests.any { it.first == "$apiPath/coverage/commits/$head/complete" }, requests.map { it.first }.toString())
        assertTrue(result.output.contains("Coverage of commit ${head.take(7)} is complete: 82.5%."), result.output)

        runner("tuistCoverageComplete", "-Ptuist.coverage.commit=0123456789abcdef").build()
        assertTrue(requests.any { it.first == "$apiPath/coverage/commits/0123456789abcdef/complete" })
    }

    // --- Fixture ---

    private fun run(result: BuildResult? = null): JsonObject {
        val match = requests.lastOrNull { it.first == apiPath }
        assertNotNull(match, "the run was not reported:\n${result?.output}")
        return JsonParser.parseString(match.second).asJsonObject
    }

    private fun body(path: String): JsonObject =
        JsonParser.parseString(requests.last { it.first == path }.second).asJsonObject

    private fun file(coverage: JsonObject, path: String): JsonObject =
        coverage.getAsJsonArray("files").map { it.asJsonObject }.firstOrNull { it.get("path").asString == path }
            ?: error("$path is not in the coverage: ${coverage.getAsJsonArray("files").map { it.asJsonObject.get("path") }}")

    private fun lineCounts(file: JsonObject): Map<Int, Int> =
        file.getAsJsonArray("line_numbers").map { it.asInt }
            .zip(file.getAsJsonArray("execution_counts").map { it.asInt })
            .toMap()

    private fun scope(evidence: JsonObject, kind: String, module: String, suite: String, name: String): JsonObject =
        evidence.getAsJsonArray("scopes").map { it.asJsonObject }.firstOrNull {
            it.get("kind").asString == kind && it.get("module").asString == module &&
                it.get("suite").asString == suite && it.get("name").asString == name
        } ?: error("no $kind scope $module/$suite/$name in ${evidence.getAsJsonArray("scopes")}")

    private fun scopePaths(evidence: JsonObject, kind: String, module: String, suite: String, name: String): List<String> {
        val paths = evidence.getAsJsonArray("paths").map { it.asString }
        return scope(evidence, kind, module, suite, name).getAsJsonArray("files").map { paths[it.asInt] }
    }

    private fun scopeLines(evidence: JsonObject, kind: String, module: String, suite: String, name: String, path: String): List<Int> {
        val scope = scope(evidence, kind, module, suite, name)
        val index = scopePaths(evidence, kind, module, suite, name).indexOf(path)
        assertTrue(index >= 0, "$path is not in the $kind scope $module/$suite/$name")
        return (scope.getAsJsonArray("lines")[index] as JsonArray).map { it.asInt }
    }

    private fun expand(ranges: List<Int>): Set<Int> =
        ranges.chunked(2).flatMap { (from, to) -> (from..to).toList() }.toSet()

    private fun line(fileName: String, text: String): Int =
        projectDir.walkTopDown().first { it.name == fileName }.readLines().indexOfFirst { it.contains(text) } + 1

    private fun blob(path: String): String = fixture.git(projectDir, "rev-parse", "HEAD:$path")

    private fun runner(vararg arguments: String, environment: Map<String, String> = emptyMap()): GradleRunner =
        GradleRunner.create()
            .withProjectDir(projectDir)
            .withArguments(arguments.toList() + listOf("--configuration-cache", "--stacktrace"))
            .withPluginClasspath()
            .withEnvironment(
                System.getenv().filterKeys { key -> key !in ciEnvironmentVariables && !key.startsWith("TUIST_") } +
                    fixture.environment +
                    mapOf(
                        "CI" to "1",
                        "TUIST_URL" to server.url("/").toString().trimEnd('/'),
                        "TUIST_TOKEN" to "test-token"
                    ) + environment
            )

    private fun writeProject(coverage: Boolean = true) {
        val coverageBlock = if (coverage) "\n    coverage {\n        enabled = true\n    }" else ""
        File(projectDir, ".gitignore").writeText("build/\n.gradle/\n.kotlin/\n")
        File(projectDir, "settings.gradle.kts").writeText(
            """
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
                uploadInBackground = false
                buildCache {
                    enabled = false
                }$coverageBlock
            }

            buildCache {
                local {
                    directory = File(rootDir, ".gradle/test-build-cache")
                }
            }

            rootProject.name = "coverage-fixture"
            include("core", "app")
            """.trimIndent()
        )
        File(projectDir, "build.gradle.kts").writeText("")
        val common = """
            plugins {
                java
            }

            dependencies {
                testImplementation(files(${classpath("junit", "opentest4j", "apiguardian")}))
            }

            // The agent from the plugin's own test classpath, so the fixture needs no repository.
            plugins.withId("jacoco") {
                dependencies {
                    "jacocoAgent"(files(${classpath("org.jacoco.agent")}))
                }
            }

            tasks.withType<Test>().configureEach {
                useJUnitPlatform()
            }
        """.trimIndent()
        write("core/build.gradle.kts", common)
        write("app/build.gradle.kts", common + "\n\ndependencies {\n    implementation(project(\":core\"))\n}\n")
        write(
            "core/src/main/java/dev/tuist/fixture/Calc.java",
            """
            package dev.tuist.fixture;

            public final class Calc {
                private static boolean warmed;

                public static void warmUp() {
                    warmed = true;
                }

                public static int add(int a, int b) {
                    return a + b;
                }

                public static int multiply(int a, int b) {
                    return a * b;
                }

                public static int unused(int a) {
                    return -a;
                }
            }
            """.trimIndent()
        )
        write(
            "core/src/test/java/dev/tuist/fixture/CalcTest.java",
            """
            package dev.tuist.fixture;

            import static org.junit.jupiter.api.Assertions.assertEquals;

            import org.junit.jupiter.api.BeforeAll;
            import org.junit.jupiter.api.Test;

            public class CalcTest {
                @BeforeAll
                static void warmUp() {
                    Calc.warmUp();
                }

                @Test
                void adds() {
                    assertEquals(3, Calc.add(1, 2));
                }

                @Test
                void multiplies() {
                    assertEquals(6, Calc.multiply(2, 3));
                }
            }
            """.trimIndent()
        )
        write(
            "app/src/main/java/dev/tuist/fixture/app/Greeter.java",
            """
            package dev.tuist.fixture.app;

            import dev.tuist.fixture.Calc;

            public final class Greeter {
                public static String greet(String name) {
                    return "Hello " + name + " " + Calc.add(1, 1);
                }
            }
            """.trimIndent()
        )
        write(
            "app/src/test/java/dev/tuist/fixture/app/GreeterTest.java",
            """
            package dev.tuist.fixture.app;

            import static org.junit.jupiter.api.Assertions.assertEquals;

            import org.junit.jupiter.api.Test;

            public class GreeterTest {
                @Test
                void greets() {
                    assertEquals("Hello Tuist 2", Greeter.greet("Tuist"));
                }
            }
            """.trimIndent()
        )
    }

    private fun write(path: String, content: String) {
        val file = File(projectDir, path)
        file.parentFile.mkdirs()
        file.writeText(content)
    }

    private fun classpath(vararg names: String): String =
        System.getProperty("java.class.path")
            .split(File.pathSeparator)
            .filter { entry -> names.any { File(entry).name.startsWith(it) } }
            .joinToString(", ") { "\"${it.replace("\\", "\\\\")}\"" }

    private val ciEnvironmentVariables = setOf(
        "CI", "GITHUB_ACTIONS", "GITHUB_RUN_ID", "GITHUB_REF", "GITHUB_HEAD_REF", "GITHUB_BASE_REF", "GITHUB_SHA",
        "GITLAB_CI", "CI_PIPELINE_ID", "CI_COMMIT_REF_NAME", "CI_MERGE_REQUEST_REF_PATH", "CI_MERGE_REQUEST_IID",
        "CI_MERGE_REQUEST_TARGET_BRANCH_NAME", "CIRCLECI", "CIRCLE_WORKFLOW_ID", "BUILDKITE", "BUILDKITE_BUILD_ID",
        "BUILDKITE_BRANCH", "BUILDKITE_PULL_REQUEST", "BUILDKITE_PULL_REQUEST_BASE_BRANCH", "CM_BUILD_ID", "BITRISE_IO"
    )
}
