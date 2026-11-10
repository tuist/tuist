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
import org.junit.jupiter.params.provider.CsvSource
import java.io.File
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class BuildEnvironmentMetadataIntegrationTest {
    @TempDir lateinit var directory: File

    @ParameterizedTest
    @CsvSource("8.14.3,false,64", "8.14.3,true,64", "9.2.1,false,64", "9.2.1,true,64", "9.2.1,false,20")
    fun `worker limits are fresh on restored configuration and metadata is backwards compatible`(version: String, background: Boolean, allowance: Int) {
        val reports = LinkedBlockingQueue<JsonObject>()
        val discovery = LinkedBlockingQueue<RecordedRequest>()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    if (request.path == "/api/metadata/limits") {
                        discovery.add(request)
                        if (allowance == 20) return MockResponse().setResponseCode(404)
                        return MockResponse().setHeader("x-tuist-custom-metadata-max-values", allowance).setBody("{}")
                    }
                    if (request.path.orEmpty().endsWith("/gradle/builds")) {
                        val report = JsonParser.parseString(request.body.readUtf8()).asJsonObject
                        if (report.getAsJsonObject("custom_metadata").getAsJsonObject("values").size() > allowance) {
                            return MockResponse().setResponseCode(400)
                        }
                        reports.add(report)
                        return MockResponse().setResponseCode(201).setBody("{\"id\":\"${report["id"].asString}\"}")
                    }
                    return MockResponse().setResponseCode(404)
                }
            }
            server.start()
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist {
                    project = 'test/metadata'
                    url = '${server.url("/")}'
                    uploadInBackground = $background
                    buildCache { enabled = false }
                    buildInsights {
                        (1..20).each { value("user." + it, "value." + it) }
                    }
                }
                rootProject.name = 'metadata'
            """.trimIndent())
            File(directory, "build.gradle").writeText("tasks.register('hello')")
            fun run(workers: Int): Pair<String, JsonObject> {
                val result = GradleRunner.create().withProjectDir(directory).withPluginClasspath().withGradleVersion(version)
                    .withEnvironment(System.getenv().filterKeys { it !in setOf("TUIST_URL", "TUIST_CACHE_ENDPOINT") } + ("TUIST_TOKEN" to "test-only"))
                    .withArguments("hello", "--configuration-cache", "--max-workers=$workers", "--no-watch-fs", "--stacktrace")
                    .build()
                return result.output to assertNotNull(reports.poll(20, TimeUnit.SECONDS), result.output)
            }
            val (_, first) = run(2)
            val (_, changed) = run(3)
            val (output, restored) = run(3)
            assertTrue(output.contains("Reusing configuration cache"), output)
            for ((report, workers) in listOf(first to 2, changed to 3, restored to 3)) {
                val values = report.getAsJsonObject("custom_metadata").getAsJsonObject("values")
                assertEquals("value.20", values["user.20"].asString)
                if (allowance > 20) {
                    assertEquals(workers.toString(), values["tuist.gradle.max_workers"]?.asString, output)
                    assertTrue(values.size() > 20)
                } else {
                    assertEquals(20, values.size())
                    assertEquals(null, values["tuist.gradle.max_workers"])
                }
            }
            assertEquals(null, assertNotNull(discovery.poll(1, TimeUnit.SECONDS)).getHeader("Authorization"))
        }
    }
}
