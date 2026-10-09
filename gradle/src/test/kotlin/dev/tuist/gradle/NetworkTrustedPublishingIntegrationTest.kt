package dev.tuist.gradle

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

class NetworkTrustedPublishingIntegrationTest {
    @TempDir lateinit var directory: File

    @Test fun `publishes without credentials or cache discovery and preserves configuration cache reuse`() {
        val requests = LinkedBlockingQueue<RecordedRequest>()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    requests.add(request)
                    return MockResponse().setResponseCode(201).setBody("{\"id\":\"server-assigned-id\"}")
                }
            }
            server.start()
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist {
                    project = 'test/network-trusted'
                    url = '${server.url("/")}'
                    uploadInBackground = false
                    network { proxy = false }
                    buildCache { enabled = false }
                    buildInsights { networkTrustedPublishing = true }
                }
                rootProject.name = 'network-trusted'
            """.trimIndent())
            File(directory, "build.gradle").writeText("tasks.register('example') { doLast { println 'example' } }")
            val environment = System.getenv().filterKeys {
                it !in setOf("TUIST_TOKEN", "TUIST_URL", "TUIST_CACHE_ENDPOINT", "TUIST_ACTOR_ID")
            } + mapOf(
                "TUIST_XDG_CONFIG_HOME" to File(directory, "config").path,
                "XDG_STATE_HOME" to File(directory, "state").path,
                "TUIST_ACTOR_ID" to "employee-123"
            )
            repeat(2) { iteration ->
                val result = GradleRunner.create().withProjectDir(directory).withPluginClasspath()
                    .withGradleVersion("9.2.1").withEnvironment(environment)
                    .withArguments("example", "--configuration-cache", "--no-watch-fs", "--stacktrace").build()
                if (iteration == 1) assertTrue(result.output.contains("Reusing configuration cache"), result.output)
                val report = assertNotNull(requests.poll(20, TimeUnit.SECONDS), result.output)
                assertEquals("/api/projects/test/network-trusted/gradle/builds", report.path)
                assertNull(report.getHeader("Authorization"))
                assertEquals("employee-123", report.getHeader("x-tuist-actor-id"))
                assertTrue(result.output.contains("server-assigned-id"), result.output)
                assertNull(requests.poll(1, TimeUnit.SECONDS), "Reporting must not discover authenticated cache endpoints")
            }
        }
    }
}
