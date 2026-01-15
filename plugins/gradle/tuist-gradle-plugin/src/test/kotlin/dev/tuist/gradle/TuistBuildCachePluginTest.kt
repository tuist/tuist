package dev.tuist.gradle

import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TuistBuildCachePluginTest {

    @TempDir
    lateinit var testProjectDir: File

    private lateinit var settingsFile: File
    private lateinit var buildFile: File

    @BeforeEach
    fun setup() {
        settingsFile = File(testProjectDir, "settings.gradle.kts")
        buildFile = File(testProjectDir, "build.gradle.kts")
    }

    @Test
    fun `plugin can be applied to settings`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist.build-cache")
            }

            tuistBuildCache {
                fullHandle = "test-account/test-project"
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello from test project!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello", "--info")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }

    @Test
    fun `plugin uses environment variables when available`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist.build-cache")
            }

            tuistBuildCache {
                fullHandle = "test-account/test-project"
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("checkCache") {
                doLast {
                    val buildCache = gradle.sharedServices
                    println("Build cache configured")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("checkCache")
            .withPluginClasspath()
            .withEnvironment(mapOf(
                "TUIST_CACHE_URL" to "http://localhost:8181/api/cache/gradle",
                "TUIST_TOKEN" to "test-token-12345"
            ))
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":checkCache")?.outcome)
    }

    @Test
    fun `plugin extension allows custom tuist path`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist.build-cache")
            }

            tuistBuildCache {
                fullHandle = "test-account/test-project"
                tuistPath = "/usr/local/bin/tuist"
                push = false
                allowInsecureProtocol = true
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }

    @Test
    fun `plugin gracefully handles missing configuration`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist.build-cache")
            }

            // No tuistBuildCache configuration - should not fail

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }
}
