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

    @Test fun `tests publish without credentials and do not read quarantine or attach an existing build`() {
        val requests = LinkedBlockingQueue<RecordedRequest>()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    requests.add(request)
                    return MockResponse().setResponseCode(200).setBody("{\"id\":\"server-id\"}")
                }
            }
            server.start()
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist {
                    project = 'test/network-tests'
                    url = '${server.url("/")}'
                    uploadInBackground = false
                    network { proxy = false }
                    buildCache { enabled = false }
                    buildInsights { networkTrustedPublishing = true }
                }
                rootProject.name = 'network-tests'
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
            val environment = System.getenv().filterKeys { it !in setOf("TUIST_TOKEN", "TUIST_URL", "TUIST_CACHE_ENDPOINT", "TUIST_NETWORK_TRUSTED_PUBLISHING") } + mapOf(
                "TUIST_XDG_CONFIG_HOME" to File(directory, "config").path,
                "XDG_STATE_HOME" to File(directory, "state").path, "TUIST_ACTOR_ID" to "employee-123", "CI" to "true"
            )
            val result = GradleRunner.create().withProjectDir(directory).withPluginClasspath().withGradleVersion("9.2.1")
                .withEnvironment(environment).withArguments("test", "--no-watch-fs", "--stacktrace").build()
            var report: RecordedRequest? = null
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
            while (System.nanoTime() < deadline && report == null) {
                val request = requests.poll(1, TimeUnit.SECONDS) ?: continue
                assertTrue(request.path?.endsWith("/gradle/builds") == true || request.path?.endsWith("/tests") == true,
                    "Reporting must not read cache or quarantine endpoints: ${request.path}")
                assertNull(request.getHeader("Authorization"))
                if (request.path?.endsWith("/tests") == true) report = request
            }
            val testReport = assertNotNull(report, result.output)
            assertEquals("employee-123", testReport.getHeader("x-tuist-actor-id"))
            val body = testReport.body.readUtf8()
            assertTrue(body.contains("ExampleTest"), body)
            assertTrue(!body.contains("gradle_build_id"), body)
            assertTrue(!body.contains("shard_plan_id"), body)
        }
    }

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
