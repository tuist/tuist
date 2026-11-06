package dev.tuist.gradle

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class BuildFailureTelemetryIntegrationTest {
    @TempDir lateinit var directory: File

    @ParameterizedTest
    @ValueSource(strings = ["8.14.3", "9.2.1"])
    fun `real compiler and configuration failures report the correct category`(version: String) {
        val reports = LinkedBlockingQueue<JsonObject>()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    if (request.path.orEmpty().endsWith("/gradle/builds")) {
                        val report = JsonParser.parseString(request.body.readUtf8()).asJsonObject
                        reports.add(report)
                        return MockResponse().setResponseCode(201).setBody("{\"id\":\"${report["id"].asString}\"}")
                    }
                    return MockResponse().setResponseCode(200).setBody("{\"endpoints\":[\"${server.url("/")}\"]}")
                }
            }
            server.start()
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist {
                    project = 'test/failures'
                    url = '${server.url("/")}'
                    uploadInBackground = false
                    buildCache { enabled = false }
                }
                rootProject.name = 'failures'
            """.trimIndent())
            File(directory, "build.gradle").writeText("plugins { id 'java' }")
            File(directory, "src/main/java/Broken.java").apply {
                parentFile.mkdirs()
                writeText("public class Broken { invalid syntax }")
            }
            fun fail(task: String): JsonObject {
                val result = GradleRunner.create().withProjectDir(directory).withPluginClasspath().withGradleVersion(version)
                    .withEnvironment(System.getenv().filterKeys { it !in setOf("TUIST_URL", "TUIST_CACHE_ENDPOINT") } + ("TUIST_TOKEN" to "test-only-token"))
                    .withArguments(task, "--configuration-cache", "--no-watch-fs", "--stacktrace").buildAndFail()
                return assertNotNull(reports.poll(20, TimeUnit.SECONDS), result.output)
            }
            val compile = fail("compileJava")
            assertEquals("failure", compile["status"].asString)
            assertEquals("verification", compile.getAsJsonObject("custom_metadata").getAsJsonObject("values")["tuist.detected_failure_category"].asString)
            File(directory, "build.gradle").appendText("\nthrow new GradleException('configuration failed')")
            val configuration = fail("help")
            assertEquals("failure", configuration["status"].asString)
            assertEquals("infrastructure_tooling", configuration.getAsJsonObject("custom_metadata").getAsJsonObject("values")["tuist.detected_failure_category"].asString)
        }
    }
}
