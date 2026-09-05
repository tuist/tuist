package dev.tuist.gradle

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
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Drives the stress gate through a real Gradle build: the plugin asks the server which
 * test cases are new, then reruns the one it is handed in nested builds, one per
 * repetition. Only the verdict is stubbed. The repetitions are real Gradle builds
 * running a real JUnit test, which is the half the unit tests cannot cover.
 */
class TuistStressNewTestsFunctionalTest {

    @TempDir
    lateinit var projectDir: File

    private lateinit var server: MockWebServer

    // The candidate's repetitions. Every repetition is a nested Gradle build, so this
    // trades fidelity against how long the suite takes; three is enough to observe an
    // alternating test both passing and failing.
    private val repetitions = 3

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                return when {
                    // The plugin resolves the account's cache endpoints before it talks to the
                    // API, so the gate never reaches the verdict without an answer here.
                    path.contains("/api/cache/endpoints") ->
                        MockResponse().setResponseCode(200)
                            .setBody("""{"endpoints":["${server.url("/").toString().trimEnd('/')}"]}""")
                    path.endsWith("/tests/stress-new-tests/verdict") ->
                        MockResponse().setResponseCode(200).setBody(
                            """
                            {"guard":null,"inventory_count":40,
                             "candidates":[{"name":"flaky()","suite_name":"dev.tuist.fixture.FlakyTest","module_name":"stress-fixture","repetitions":$repetitions,"excluded_reason":null}],
                             "parameters":{"candidate_cap":200,"wall_clock_ceiling_ms":600000,"bulk_change_ratio":0.3,"bulk_change_floor":50,"repetition_curve":[]}}
                            """.trimIndent()
                        )
                    // Everything else the plugin reports during a build (test results,
                    // quarantine lookups) is answered emptily: the gate is what is under test.
                    else -> MockResponse().setResponseCode(200).setBody("{}")
                }
            }
        }
        server.start()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `reruns a new test case and reports the repetitions that failed`() {
        writeProject(mode = "report")

        val result = runner().build()

        assertTrue(
            result.output.contains("Tuist: Stress-testing new tests"),
            "the gate did not run:\n${result.output}"
        )
        assertTrue(
            result.output.contains("$repetitions repetitions, 2 failed"),
            "expected an alternating test to fail 2 of its $repetitions repetitions:\n${result.output}"
        )
        assertEquals(repetitions, nestedBuildCount(), "one nested build per repetition")
    }

    @Test
    fun `enforce fails the build on a test case that proves flaky`() {
        writeProject(mode = "enforce")

        val result = runner().buildAndFail()

        assertTrue(
            result.output.contains("failed 2 of $repetitions repetitions"),
            "the gate did not report the flaky candidate:\n${result.output}"
        )
    }

    private fun runner(): GradleRunner =
        GradleRunner.create()
            .withProjectDir(projectDir)
            .withArguments("test", "--stacktrace")
            .withPluginClasspath()
            .withEnvironment(
                System.getenv() + mapOf(
                    "TUIST_URL" to server.url("/").toString().trimEnd('/'),
                    "TUIST_TOKEN" to "test-token",
                    "FLAKY_COUNTER" to counterFile().absolutePath
                )
            )

    private fun counterFile() = File(projectDir, "flaky-counter")

    // The fixture test appends one line per execution, so the file counts every JVM
    // that ran it: the first pass plus one per repetition.
    private fun nestedBuildCount(): Int =
        counterFile().readLines().count { it.isNotBlank() } - 1

    private fun writeProject(mode: String) {
        // The plugin comes in on a file classpath rather than through `plugins { id(...) }`.
        // TestKit injects its classpath into the build it launches only, and every repetition
        // is a nested Gradle build that re-evaluates this file, so an injected plugin would be
        // unresolvable there. Files are resolvable in both.
        File(projectDir, "settings.gradle.kts").writeText(
            """
            import dev.tuist.gradle.TuistExtension

            buildscript {
                dependencies {
                    classpath(files(${pluginClasspath()}))
                }
            }

            apply(plugin = "dev.tuist")

            configure<TuistExtension> {
                project = "test-account/test-project"
                stressNewTests {
                    mode = "$mode"
                }
            }

            rootProject.name = "stress-fixture"
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
                environment("FLAKY_COUNTER", System.getenv("FLAKY_COUNTER"))
            }
            """.trimIndent()
        )

        val testSource = File(projectDir, "src/test/java/dev/tuist/fixture/FlakyTest.java")
        testSource.parentFile.mkdirs()
        testSource.writeText(
            """
            package dev.tuist.fixture;

            import static org.junit.jupiter.api.Assertions.fail;

            import java.io.IOException;
            import java.nio.file.Files;
            import java.nio.file.Path;
            import java.nio.file.Paths;
            import java.nio.file.StandardOpenOption;
            import java.util.List;
            import org.junit.jupiter.api.Test;

            public class FlakyTest {
                // Alternates pass, fail, pass, fail across processes, so the gate observes a
                // test case that genuinely disagrees between repetitions rather than one that
                // always fails. The counter is a file because every repetition is a fresh JVM.
                @Test
                public void flaky() throws IOException {
                    Path counter = Paths.get(System.getenv("FLAKY_COUNTER"));
                    long runs = Files.exists(counter) ? Files.readAllLines(counter).size() : 0;
                    Files.write(
                        counter,
                        List.of("run"),
                        StandardOpenOption.CREATE,
                        StandardOpenOption.APPEND
                    );
                    if (runs % 2 == 1) {
                        fail("flaky on run " + runs);
                    }
                }

                @Test
                public void stable() {
                }
            }
            """.trimIndent()
        )
    }

    private fun pluginClasspath(): String =
        GradleRunner.create().withPluginClasspath().pluginClasspath.joinToString(", ") {
            "\"${it.absolutePath.replace("\\", "\\\\")}\""
        }

    // The fixture build has no repositories, so JUnit comes from the jars already on this
    // suite's own runtime classpath. Keeps the functional test hermetic and offline.
    private fun junitClasspath(): String =
        System.getProperty("java.class.path")
            .split(File.pathSeparator)
            .filter { it.contains("junit") || it.contains("opentest4j") || it.contains("apiguardian") }
            .joinToString(", ") { "\"${it.replace("\\", "\\\\")}\"" }
}
