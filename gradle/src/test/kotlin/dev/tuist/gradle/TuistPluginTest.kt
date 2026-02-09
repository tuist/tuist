package dev.tuist.gradle

import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

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
                project = "test-account/test-project"
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
    fun `plugin gracefully handles missing project`() {
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
    fun `plugin warns when project is blank`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = ""
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
            .withArguments("hello", "--warn")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
        assertTrue(result.output.contains("project not configured"))
    }

    @Test
    fun `build cache can be disabled`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"

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
        assertTrue(result.output.contains("Build cache is disabled"))
    }

    @Test
    fun `plugin extension allows custom executable path`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
                executablePath = "/usr/local/bin/tuist"

                buildCache {
                    push = false
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
    fun `build cache push can be disabled`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"

                buildCache {
                    enabled = true
                    push = false
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
    fun `build cache allowInsecureProtocol can be enabled`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"

                buildCache {
                    enabled = true
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
    fun `custom server URL can be configured`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
                url = "https://custom.server.dev"
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
    fun `build insights logs message when configured`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "my-org/my-project"

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
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
        assertTrue(result.output.contains("Build insights configured for my-org/my-project"))
    }

    @Test
    fun `plugin logs message when build cache is configured`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "my-org/my-project"

                buildCache {
                    enabled = true
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
        assertTrue(result.output.contains("Remote build cache configured for my-org/my-project"))
    }
}
