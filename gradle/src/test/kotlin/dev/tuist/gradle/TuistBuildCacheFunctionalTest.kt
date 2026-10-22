package dev.tuist.gradle

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.gradle.testkit.runner.BuildResult
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.security.MessageDigest
import java.util.HexFormat
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Drives the Tuist build cache through real Gradle builds, with the cache endpoint served
 * by a mock server, to check how Gradle itself handles an entry whose body fails checksum
 * verification.
 */
class TuistBuildCacheFunctionalTest {

    @TempDir
    lateinit var projectDir: File

    private lateinit var server: MockWebServer

    private val entries = ConcurrentHashMap<String, ByteArray>()
    private val uploadedChecksums = ConcurrentHashMap<String, String>()
    private val requests = ConcurrentLinkedQueue<RecordedRequest>()

    @Volatile
    private var cacheTokenResponse: () -> MockResponse = { MockResponse().setResponseCode(404) }

    @Volatile
    private var servedChecksum: (ByteArray) -> String = ::sha256

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.requestUrl?.encodedPath.orEmpty()
                requests += request
                return when {
                    path.startsWith("/api/cache/gradle/") && request.method == "PUT" -> {
                        val body = request.body.readByteArray()
                        entries[path] = body
                        request.getHeader("tuist-checksum-sha256")?.let { uploadedChecksums[path] = it }
                        MockResponse().setResponseCode(201)
                    }
                    path.startsWith("/api/cache/gradle/") ->
                        entries[path]
                            ?.let { body ->
                                MockResponse()
                                    .setBody(Buffer().write(body))
                                    .addHeader("tuist-checksum-sha256", servedChecksum(body))
                            }
                            ?: MockResponse().setResponseCode(404)
                    path == "/api/cache/token" -> cacheTokenResponse()
                    path.endsWith("/gradle/builds") ->
                        MockResponse().setResponseCode(201).setBody("""{"id":"build"}""")
                    else -> MockResponse().setResponseCode(200).setBody("{}")
                }
            }
        }
        server.start()
        writeProject()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `executes the task when a remote entry does not match its checksum`() {
        val cold = run("produce")
        assertEquals(TaskOutcome.SUCCESS, cold.task(":produce")?.outcome, cold.output)
        val (entryPath, entry) = entries.entries.single()
        assertEquals(sha256(entry), uploadedChecksums[entryPath])

        servedChecksum = { body -> sha256(body + 0.toByte()) }
        val mismatched = run("clean", "produce")
        assertEquals(TaskOutcome.SUCCESS, mismatched.task(":produce")?.outcome, mismatched.output)
        assertTrue(
            mismatched.output.contains("Treating remote cache entry"),
            "expected a warning about the mismatched entry:\n${mismatched.output}"
        )
        assertFalse(
            mismatched.output.contains("disabled during the build"),
            "a mismatched entry must not disable the remote cache:\n${mismatched.output}"
        )
        assertEquals("produced", File(projectDir, "build/produced.txt").readText())

        servedChecksum = ::sha256
        val warm = run("clean", "produce")
        assertEquals(TaskOutcome.FROM_CACHE, warm.task(":produce")?.outcome, warm.output)
        assertEquals("produced", File(projectDir, "build/produced.txt").readText())
    }

    @Test
    fun `sends cache nodes the exchanged token and the server the credential`() {
        cacheTokenResponse = { MockResponse().setBody("""{"token":"cache-token","expires_in":1800}""") }

        val cold = run("produce")
        assertEquals(TaskOutcome.SUCCESS, cold.task(":produce")?.outcome, cold.output)
        val warm = run("clean", "produce")
        assertEquals(TaskOutcome.FROM_CACHE, warm.task(":produce")?.outcome, warm.output)

        val exchanges = requests.filter { it.requestUrl?.encodedPath == "/api/cache/token" }
        assertEquals(2, exchanges.size, "one exchange per build")
        exchanges.forEach { exchange ->
            assertEquals("POST", exchange.method)
            assertEquals("test/cache", exchange.requestUrl?.queryParameter("full_handle"))
            assertEquals("Bearer test-token", exchange.getHeader("Authorization"))
        }
        val cacheRequests = requests.filter { it.requestUrl?.encodedPath.orEmpty().startsWith("/api/cache/gradle/") }
        assertEquals(setOf("PUT", "GET"), cacheRequests.map { it.method }.toSet())
        assertEquals(setOf("Bearer cache-token"), cacheRequests.map { it.getHeader("Authorization") }.toSet())
        val serverRequests = requests.filter { it.requestUrl?.encodedPath.orEmpty().endsWith("/gradle/builds") }
        assertTrue(serverRequests.isNotEmpty(), "expected build reports")
        assertEquals(setOf("Bearer test-token"), serverRequests.map { it.getHeader("Authorization") }.toSet())
    }

    @Test
    fun `sends cache nodes the credential when the server cannot exchange it`() {
        cacheTokenResponse = { MockResponse().setResponseCode(404) }

        val cold = run("produce")
        assertEquals(TaskOutcome.SUCCESS, cold.task(":produce")?.outcome, cold.output)

        val upload = requests.single { it.requestUrl?.encodedPath.orEmpty().startsWith("/api/cache/gradle/") && it.method == "PUT" }
        assertEquals("Bearer test-token", upload.getHeader("Authorization"))
    }

    @Test
    fun `disables the remote cache without falling back to the credential when the free tier is exhausted`() {
        cacheTokenResponse = {
            MockResponse().setResponseCode(402).setBody("""{"message":"The free tier of test is exhausted."}""")
        }

        val cold = run("produce")

        assertEquals(TaskOutcome.SUCCESS, cold.task(":produce")?.outcome, cold.output)
        assertTrue(cold.output.contains("The free tier of test is exhausted."), cold.output)
        assertTrue(
            requests.none { it.requestUrl?.encodedPath.orEmpty().startsWith("/api/cache/gradle/") },
            "no cache request may be sent with the credential"
        )
    }

    private fun run(vararg tasks: String): BuildResult =
        GradleRunner.create()
            .withProjectDir(projectDir)
            .withPluginClasspath()
            .withEnvironment(
                System.getenv() + mapOf(
                    "TUIST_URL" to server.url("/").toString().trimEnd('/'),
                    "TUIST_CACHE_ENDPOINT" to server.url("/").toString().trimEnd('/'),
                    "TUIST_TOKEN" to "test-token"
                )
            )
            .withArguments(tasks.toList() + listOf("--build-cache", "--no-watch-fs", "--stacktrace"))
            .build()

    private fun writeProject() {
        File(projectDir, "settings.gradle").writeText(
            """
            plugins { id 'dev.tuist' }
            tuist {
                project = 'test/cache'
                uploadInBackground = false
            }
            buildCache { local { enabled = false } }
            rootProject.name = 'cache-integrity'
            """.trimIndent()
        )
        File(projectDir, "build.gradle").writeText(
            """
            plugins { id 'base' }
            tasks.register('produce') {
                def output = layout.buildDirectory.file('produced.txt')
                inputs.property('content', 'produced')
                outputs.file(output)
                outputs.cacheIf { true }
                doLast { output.get().asFile.text = 'produced' }
            }
            """.trimIndent()
        )
    }

    private fun sha256(bytes: ByteArray): String =
        HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes))
}
