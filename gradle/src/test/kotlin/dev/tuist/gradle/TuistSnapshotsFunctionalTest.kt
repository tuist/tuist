package dev.tuist.gradle

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals

class TuistSnapshotsFunctionalTest {
    @TempDir lateinit var directory: File

    @Test
    fun `debug unit tests upload the generated preview snapshots in CI only, unless the property says otherwise`() {
        fixture()

        fun uploads(ci: Boolean, vararg args: String): Boolean =
            runner(ci, ":app:testDebugUnitTest", "-m", "--configuration-cache", *args).build().output
                .contains(":app:tuistUploadSnapshots SKIPPED")

        assertEquals(true, uploads(ci = true), "CI")
        // The configuration cache entry stored in CI must not be reused locally.
        assertEquals(false, uploads(ci = false), "local")
        assertEquals(true, uploads(ci = false, "-Ptuist.snapshots=true"), "local with -Ptuist.snapshots=true")
        assertEquals(false, uploads(ci = true, "-Ptuist.snapshots=false"), "CI with -Ptuist.snapshots=false")
        // Release unit tests render the same previews; only debug uploads, so `test` uploads once.
        assertEquals(
            false,
            runner(true, ":app:testReleaseUnitTest", "-m").build().output.contains(":app:tuistUploadSnapshots"),
            "CI, release unit tests"
        )
    }

    private fun fixture() {
        val sdk = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
        assumeTrue(sdk != null && File(sdk, "platforms/android-35").isDirectory, "Requires Android SDK 35")
        File(directory, "local.properties").writeText("sdk.dir=$sdk\n")
        File(directory, "gradle.properties").writeText("android.useAndroidX=true\n")
        File(directory, "settings.gradle").writeText("""
            pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
            plugins { id 'dev.tuist' }
            dependencyResolutionManagement { repositories { google(); mavenCentral() } }
            tuist {
                project = 'test-account/test-project'
                url = 'http://127.0.0.1:1'
                network { proxy = false }
                buildCache { enabled = false }
                uploadInBackground = false
                testQuarantine { enabled = false }
                snapshots {
                    enabled = true
                    set = 'android-phone'
                }
            }
            rootProject.name = 'snapshots-fixture'
            include ':app'
        """.trimIndent())
        File(directory, "build.gradle").writeText("""
            plugins {
                id 'com.android.application' version '8.8.2' apply false
                id 'app.cash.paparazzi' version '1.3.5' apply false
            }
        """.trimIndent())
        val app = File(directory, "app").apply { mkdirs() }
        File(app, "build.gradle").writeText("""
            plugins {
                id 'com.android.application'
                id 'app.cash.paparazzi'
            }
            android {
                namespace 'dev.tuist.snapshots.fixture'
                compileSdk 35
                defaultConfig { minSdk 26; targetSdk 35 }
            }
        """.trimIndent())
        File(app, "src/main/AndroidManifest.xml").apply { parentFile.mkdirs() }.writeText(
            """<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application/></manifest>"""
        )
    }

    private fun runner(ci: Boolean, vararg args: String): GradleRunner {
        val environment = System.getenv().filterKeys { !it.startsWith("TUIST_") && it != "CI" } +
            ("TUIST_TOKEN" to "fixture-token") + (if (ci) mapOf("CI" to "true") else emptyMap())
        return GradleRunner.create()
            .withProjectDir(directory).withPluginClasspath().withGradleVersion("8.12.1")
            .withEnvironment(environment)
            .withArguments(*args, "--stacktrace", "--max-workers=2", "--no-watch-fs")
    }
}
