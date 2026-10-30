package dev.tuist.gradle

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.Test
import java.net.HttpURLConnection
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BuildEnvironmentMetadataTest {
    @Test
    fun `observations are strings and explicit metadata wins`() {
        val observations = buildEnvironmentMetadata(
            properties = { mapOf("os.name" to "Linux", "os.version" to "6.12", "os.arch" to "aarch64")[it] },
            environment = emptyMap(), processors = { 28 }, memory = { null }, heap = { 1024 },
            locale = { "en-GB" }, charset = { "UTF-8" }, maxWorkers = 14
        )
        assertEquals("linux", observations["tuist.os.type"])
        assertEquals("aarch64", observations["tuist.host.arch"])
        assertEquals("28", observations["tuist.cpu.available_processors"])
        assertEquals("14", observations["tuist.gradle.max_workers"])
        assertFalse(observations.containsKey("tuist.memory.total_bytes"))
        val metadata = BuildCustomMetadata(values = mapOf("tuist.gradle.max_workers" to "7"))
            .withObservations(observations)
        assertEquals("7", metadata.values["tuist.gradle.max_workers"])
    }

    @Test
    fun `legacy budget never evicts explicit values`() {
        val explicit = (1..20).associate { "user.$it" to "$it" }
        assertEquals(explicit, BuildCustomMetadata(values = explicit).withObservations(mapOf("tuist.os.type" to "linux")).values)
        val expanded = BuildCustomMetadata(values = explicit).withObservations(mapOf("tuist.future.key" to "value"), 64)
        assertEquals(21, expanded.values.size)
        assertTrue(expanded.values.entries.containsAll(explicit.entries))
    }

    @Test
    fun `probe errors are omitted and runner identifiers require opt in`() {
        val environment = mapOf("GITHUB_ACTIONS" to "true", "RUNNER_NAME" to "private-machine", "SECRET" to "never-send")
        fun collect(env: Map<String, String>) = buildEnvironmentMetadata(
            properties = { null }, environment = env,
            processors = { throw IllegalStateException() }, memory = { null }, heap = { 0 },
            locale = { "en-US" }, charset = { "UTF-8" }
        )
        val values = collect(environment)
        assertFalse(values.containsKey("tuist.cpu.available_processors"))
        assertFalse(values.values.contains("never-send"))
        assertFalse(values.containsKey("tuist.ci.runner_name"))
        assertEquals("private-machine", collect(environment + ("TUIST_BUILD_METADATA_RUNNER_NAME" to "1"))["tuist.ci.runner_name"])
    }

    @Test
    fun `discovery requires explicit bounded support and never redirects or authenticates`() {
        MockWebServer().use { server ->
            server.start()
            fun discover() = discoverBuildMetadataLimit(server.url("/").toUri()) {
                it.toURL().openConnection() as HttpURLConnection
            }
            for ((header, expected) in listOf(null to 20, "64" to 64, "999999" to 20, "garbage" to 20)) {
                val response = MockResponse().setBody("{}")
                if (header != null) response.setHeader("x-tuist-custom-metadata-max-values", header)
                server.enqueue(response)
                assertEquals(expected, discover())
                val request = server.takeRequest()
                assertEquals("/api/metadata/limits", request.path)
                assertEquals(null, request.getHeader("Authorization"))
                assertEquals(0, request.bodySize)
            }
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", server.url("/other")))
            assertEquals(20, discover())
            assertEquals("/api/metadata/limits", server.takeRequest().path)
            assertEquals(5, server.requestCount)
        }
    }
}
