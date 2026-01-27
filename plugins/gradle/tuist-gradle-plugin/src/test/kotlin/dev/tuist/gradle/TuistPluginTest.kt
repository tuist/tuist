package dev.tuist.gradle

import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals

class TuistPluginTest {

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
                id("dev.tuist")
            }

            tuist {
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
    fun `plugin extension allows custom tuist path`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                fullHandle = "test-account/test-project"
                tuistPath = "/usr/local/bin/tuist"

                buildCache {
                    push = false
                    allowInsecureProtocol = true
                }
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
    fun `plugin gracefully handles missing fullHandle`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            // No tuist configuration - should not fail, just warn

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
    fun `build cache can be disabled`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                fullHandle = "test-account/test-project"

                buildCache {
                    enabled = false
                }
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
            .withArguments("hello", "--info")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }
}
