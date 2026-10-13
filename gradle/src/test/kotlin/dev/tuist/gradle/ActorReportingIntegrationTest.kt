package dev.tuist.gradle

import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ActorReportingIntegrationTest {
    @TempDir lateinit var directory: File

    @Test fun `authenticated builds and tests tolerate a legacy server ignoring actor headers`() {
        val requests = LinkedBlockingQueue<RecordedRequest>()
        val nonReports = LinkedBlockingQueue<RecordedRequest>()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val report = request.method == "POST" && (request.path?.endsWith("/gradle/builds") == true || request.path?.endsWith("/tests") == true)
                    if (report) {
                        requests.add(request)
                        val body = JsonParser.parseString(request.body.clone().readUtf8()).asJsonObject
                        val status = if (request.path?.endsWith("/gradle/builds") == true) 201 else 200
                        val id = body["id"]?.asString ?: "server-test-id"
                        return MockResponse().setResponseCode(status).setBody("{\"id\":\"$id\"}")
                    }
                    nonReports.add(request)
                    return MockResponse().setResponseCode(200).setBody("{\"endpoints\":[\"${server.url("/")}\"],\"test_cases\":[]}")
                }
            }
            server.start()
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist {
                    project = 'test/actor-compatibility'
                    url = '${server.url("/")}'
                    uploadInBackground = false
                    network { proxy = false }
                    buildCache { enabled = false }
                    testQuarantine { enabled = true }
                    buildInsights { actorId = 'configured-actor' }
                }
                rootProject.name = 'actor-compatibility'
            """.trimIndent())
            File(directory, "build.gradle").writeText("""
                plugins { id 'java' }
                repositories { mavenCentral() }
                dependencies { testImplementation 'junit:junit:4.13.2' }
            """.trimIndent())
            File(directory, "src/test/java/ExampleTest.java").apply {
                parentFile.mkdirs()
                writeText("public class ExampleTest { @org.junit.Test public void reports() { org.junit.Assert.assertTrue(true); } }")
            }
            val environment = System.getenv().filterKeys { it !in setOf("TUIST_URL", "TUIST_CACHE_ENDPOINT", "TUIST_ACTOR_ID") } + mapOf(
                "TUIST_TOKEN" to "existing-token",
                "TUIST_XDG_CONFIG_HOME" to File(directory, "config").path,
                "XDG_STATE_HOME" to File(directory, "state").path,
                "CI" to "true"
            )
            listOf(null, "environment-actor", "", "invalid actor").forEachIndexed { iteration, override ->
                val runEnvironment = environment.toMutableMap().apply {
                    if (override != null) put("TUIST_ACTOR_ID", override)
                }
                val result = GradleRunner.create().withProjectDir(directory).withPluginClasspath().withGradleVersion("9.2.1")
                    .withEnvironment(runEnvironment).withArguments("test", "--rerun-tasks", "--configuration-cache", "--no-watch-fs", "--stacktrace").build()
                if (iteration > 0) assertTrue(result.output.contains("Reusing configuration cache"), result.output)
                val reports = List(2) { assertNotNull(requests.poll(20, TimeUnit.SECONDS), result.output) }
                assertEquals(setOf("/api/projects/test/actor-compatibility/gradle/builds", "/api/projects/test/actor-compatibility/tests"), reports.map { it.path }.toSet())
                assertTrue(nonReports.isNotEmpty(), "The fixture must exercise non-report requests")
                nonReports.forEach { request ->
                    assertNull(request.getHeader(ActorIdentifier.HEADER), request.path)
                }
                reports.forEach { request ->
                    assertEquals("Bearer existing-token", request.getHeader("Authorization"))
                    val expectedActor = when (iteration) {
                        0 -> "configured-actor"
                        1 -> "environment-actor"
                        else -> null
                    }
                    assertEquals(expectedActor, request.getHeader(ActorIdentifier.HEADER))
                    val payload = JsonParser.parseString(request.body.readUtf8()).asJsonObject
                    assertEquals("success", payload["status"].asString)
                    assertTrue(!payload.has("actor_id") && !payload.has("actor_account_id") && !payload.has("submission_auth"), payload.toString())
                    if (request.path?.endsWith("/tests") == true) {
                        assertTrue(payload.toString().contains("ExampleTest"), payload.toString())
                    } else {
                        assertTrue(payload.has("id"), payload.toString())
                    }
                }
            }
        }
    }
}
