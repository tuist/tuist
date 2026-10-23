package dev.tuist.gradle

import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class ReportReplayIntegrationTest {
    @TempDir lateinit var directory: File

    private enum class FirstAttempt { DROPPED, BAD_GATEWAY }

    private val buildsPath = "/api/projects/test/replay/gradle/builds"
    private val testsPath = "/api/projects/test/replay/tests"

    @Test
    fun `build and test reports are resent with the same id after a dropped connection or a 502`() {
        val ids = ConcurrentHashMap<String, CopyOnWriteArrayList<String?>>()
        val failures = ConcurrentHashMap<String, FirstAttempt>()
        val arrivals = ConcurrentHashMap<String, AtomicInteger>()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val path = request.path.orEmpty()
                    if (request.method != "POST" || (path != buildsPath && path != testsPath)) {
                        return MockResponse().setResponseCode(200).setBody("{\"endpoints\":[\"${server.url("/")}\"],\"test_cases\":[]}")
                    }
                    val body = JsonParser.parseString(request.body.readUtf8()).asJsonObject
                    val id = body["id"]?.takeIf { !it.isJsonNull }?.asString
                    ids.getOrPut(path) { CopyOnWriteArrayList() }.add(id)
                    val arrival = arrivals.getOrPut(path) { AtomicInteger() }.incrementAndGet()
                    // HttpURLConnection silently resends a buffered POST once when the connection closes
                    // without a response, so two arrivals are dropped to reach the plugin's own retry.
                    when (failures[path]) {
                        FirstAttempt.DROPPED -> if (arrival <= 2) {
                            return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)
                        }
                        FirstAttempt.BAD_GATEWAY -> if (arrival == 1) {
                            return MockResponse().setResponseCode(502).setBody("upstream connect error")
                        }
                        null -> Unit
                    }
                    val status = if (path == buildsPath) 201 else 200
                    return MockResponse().setResponseCode(status).setBody("{\"id\":\"${id ?: "server-generated-id"}\"}")
                }
            }
            server.start()
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist {
                    project = 'test/replay'
                    url = '${server.url("/")}'
                    uploadInBackground = false
                    network { proxy = false }
                    buildCache { enabled = false }
                    testQuarantine { enabled = false }
                }
                rootProject.name = 'replay'
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
                "TUIST_GIT_UPLOAD_ENABLED" to "false"
            )

            val reportedIds = listOf(
                mapOf(buildsPath to FirstAttempt.DROPPED, testsPath to FirstAttempt.BAD_GATEWAY),
                mapOf(buildsPath to FirstAttempt.BAD_GATEWAY, testsPath to FirstAttempt.DROPPED)
            ).map { scenario ->
                ids.clear()
                arrivals.clear()
                failures.clear()
                failures.putAll(scenario)

                val result = GradleRunner.create().withProjectDir(directory).withPluginClasspath().withGradleVersion("9.2.1")
                    .withEnvironment(environment).withArguments("test", "--rerun-tasks", "--no-watch-fs", "--stacktrace").build()

                listOf(buildsPath, testsPath).associateWith { path ->
                    val sent = ids[path].orEmpty()
                    val expectedRequests = if (scenario[path] == FirstAttempt.DROPPED) 3 else 2
                    assertEquals(expectedRequests, sent.size, "$path received $sent\n${result.output}")
                    val id = sent.first()
                    assertTrue(id != null && UUID.fromString(id).toString() == id, "$path sent id $id")
                    assertTrue(sent.all { it == id }, "$path resent different ids: $sent")
                    val reported = if (path == buildsPath) "build $id" else "test run $id"
                    assertTrue(result.output.contains("reported successfully ($reported)"), result.output)
                    id!!
                }
            }

            listOf(buildsPath, testsPath).forEach { path ->
                assertNotEquals(reportedIds[0][path], reportedIds[1][path], "$path must get a new id every build")
            }
        }
    }
}
