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
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ReportOutboxIntegrationTest {
    @TempDir lateinit var directory: File

    private data class Arrival(val path: String, val id: String, val body: String)

    @Test
    fun `reports a build could not deliver are sent by the next build with the same id and body`() {
        val project = "outbox${UUID.randomUUID().toString().take(8)}"
        val buildsPath = "/api/projects/test/$project/gradle/builds"
        val testsPath = "/api/projects/test/$project/tests"
        val arrivals = CopyOnWriteArrayList<Arrival>()
        val serverAvailable = AtomicBoolean(false)
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val path = request.path.orEmpty()
                    if (request.method != "POST" || (path != buildsPath && path != testsPath)) {
                        return MockResponse().setResponseCode(404)
                    }
                    val body = request.body.readUtf8()
                    val id = JsonParser.parseString(body).asJsonObject["id"].asString
                    arrivals.add(Arrival(path, id, body))
                    return when {
                        serverAvailable.get() -> MockResponse().setResponseCode(if (path == buildsPath) 201 else 200).setBody("{\"id\":\"$id\"}")
                        path == buildsPath -> MockResponse().setResponseCode(503)
                        else -> MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)
                    }
                }
            }
            server.start()
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist {
                    project = 'test/$project'
                    url = '${server.url("/")}'
                    uploadInBackground = false
                    network { proxy = false }
                    buildCache { enabled = false }
                    testQuarantine { enabled = false }
                }
                rootProject.name = 'outbox'
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
            val build = {
                GradleRunner.create().withProjectDir(directory).withPluginClasspath().withGradleVersion("9.2.1")
                    .withEnvironment(environment).withArguments("test", "--rerun-tasks", "--no-watch-fs", "--stacktrace").build()
            }

            val unavailable = build()
            assertTrue(unavailable.output.contains("Failed to send build insights"), unavailable.output)
            assertTrue(unavailable.output.contains("Failed to send test insights"), unavailable.output)
            val undelivered = listOf(buildsPath, testsPath).associateWith { path -> arrivals.first { it.path == path } }

            arrivals.clear()
            serverAvailable.set(true)
            val available = build()

            undelivered.forEach { (path, original) ->
                val resent = arrivals.filter { it.path == path && it.id == original.id }
                assertEquals(1, resent.size, "$path: ${arrivals.map { it.path to it.id }}\n${available.output}")
                assertEquals(original.body, resent.single().body)
            }
            listOf(buildsPath, testsPath).forEach { path ->
                assertEquals(2, arrivals.count { it.path == path }, "$path: ${arrivals.map { it.path to it.id }}")
            }

            arrivals.clear()
            build()
            assertTrue(arrivals.none { arrival -> undelivered.values.any { it.id == arrival.id } }, "$arrivals")
        }
    }
}
