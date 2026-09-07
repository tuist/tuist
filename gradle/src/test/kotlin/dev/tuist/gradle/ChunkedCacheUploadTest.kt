package dev.tuist.gradle

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.caching.BuildCacheEntryWriter
import org.gradle.caching.BuildCacheKey
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.OutputStream
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.concurrent.atomic.AtomicLong
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ChunkedCacheUploadTest {
    @TempDir lateinit var directory: File
    private fun service(base: String, project: String = "project", push: Boolean = true, chunks: File? = null) = TuistBuildCacheService(
        TuistHttpClient(object : ConfigurationProvider {
            override fun getConfiguration(forceRefresh: Boolean) = CacheConfiguration(base, "test", "chunking-test", project)
        }), push, chunks
    )

    private fun key(value: String) = object : BuildCacheKey {
        override fun getHashCode() = value
        override fun toByteArray() = value.toByteArray()
    }

    private fun writer(bytes: ByteArray) = object : BuildCacheEntryWriter {
        override fun getSize() = bytes.size.toLong()
        override fun writeTo(output: OutputStream) { output.write(bytes) }
    }

    @Test fun `old servers and malformed capabilities retain whole upload behavior`() {
        for ((status, body) in listOf(404 to "", 501 to "", 200 to "{}", 200 to "not-json")) {
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setResponseCode(status).setBody(body))
                server.enqueue(MockResponse().setResponseCode(201))
                val bytes = ByteArray(2 * 1024 * 1024)
                service(server.url("/").toString()).store(key("abcd"), writer(bytes))
                assertTrue(server.takeRequest().path!!.startsWith("/api/cache/chunks/capabilities"))
                val put = server.takeRequest()
                assertEquals("PUT", put.method)
                assertTrue(put.path!!.startsWith("/api/cache/gradle/abcd"))
                assertContentEquals(bytes, put.body.readByteArray())
            }
        }
    }

    @Test fun `small uploads and disabled push do not probe capabilities`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(201))
            service(server.url("/").toString()).store(key("abcd"), writer(byteArrayOf(1, 2, 3)))
            assertTrue(server.takeRequest().path!!.startsWith("/api/cache/gradle/"))
            service(server.url("/").toString(), push = false).store(key("abce"), writer(ByteArray(2 * 1024 * 1024)))
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun `mixed version node falls back without invoking the writer twice`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("""{"version":1,"algorithm":"fastcdc2020","average_chunk_bytes":524288,"seed":0,"normalization":2,"minimum_blob_bytes":2097152,"maximum_chunk_bytes":2097152,"maximum_chunks":16384}"""))
            server.enqueue(MockResponse().setResponseCode(404))
            server.enqueue(MockResponse().setResponseCode(201))
            val bytes = chunkingCorpus()
            var writes = 0
            service(server.url("/").toString()).store(key("abcd"), object : BuildCacheEntryWriter {
                override fun getSize() = bytes.size.toLong()
                override fun writeTo(output: OutputStream) { writes++; output.write(bytes) }
            })
            assertEquals(1, writes)
            server.takeRequest()
            server.takeRequest()
            assertContentEquals(bytes, server.takeRequest().body.readByteArray())
        }
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TUIST_CHUNKING_TEST_URL", matches = "http://127\\.0\\.0\\.1:[0-9]+")
    fun `production client round trips through local Kura with fewer uploaded bytes`() {
        val base = System.getenv("TUIST_CHUNKING_TEST_URL")
        val uploaded = AtomicLong()
        val downloaded = AtomicLong()
        val metadata = AtomicLong()
        val requests = AtomicLong()
        val forwarding = HttpClient.newHttpClient()
        MockWebServer().use { proxy ->
            proxy.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val bytes = request.body.readByteArray()
                    if (request.path!!.startsWith("/api/cache/chunks/upload")) uploaded.addAndGet(bytes.size.toLong())
                    else metadata.addAndGet(bytes.size.toLong())
                    requests.incrementAndGet()
                    val builder = HttpRequest.newBuilder(URI.create(base + request.path)).method(request.method!!, HttpRequest.BodyPublishers.ofByteArray(bytes))
                    request.getHeader("Content-Type")?.let { builder.header("Content-Type", it) }
                    val response = forwarding.send(builder.build(), HttpResponse.BodyHandlers.ofByteArray())
                    if (request.path!!.startsWith("/api/cache/chunks/download")) downloaded.addAndGet(response.body().size.toLong())
                    return MockResponse().setResponseCode(response.statusCode()).setBody(okio.Buffer().write(response.body()))
                }
            }
            val project = "gradle-chunks-${System.nanoTime()}"
            val service = service(proxy.url("/").toString(), project)
            val original = chunkingCorpus()
            val insertion = original.copyOfRange(0, 1_000_000) + "an insertion".toByteArray() + original.copyOfRange(1_000_000, original.size)
            val fixtures = System.getenv("TUIST_CHUNKING_ARTIFACTS")?.split(':')?.map { File(it).readBytes() } ?: emptyList()
            for ((index, bytes) in (listOf(original, insertion) + fixtures).withIndex()) {
                val compressed = java.io.ByteArrayOutputStream().also { buffer -> GZIPOutputStream(buffer).use { it.write(bytes) } }.toByteArray()
                val before = uploaded.get()
                val metadataBefore = metadata.get()
                val requestsBefore = requests.get()
                val started = System.nanoTime()
                service.store(key("abcd$index"), writer(compressed))
                val elapsed = (System.nanoTime() - started) / 1e6
                val sent = uploaded.get() - before
                println("BENCH gradle phase=$index legacy_bytes=${compressed.size} uploaded_bytes=$sent metadata_bytes=${metadata.get() - metadataBefore} requests=${requests.get() - requestsBefore} elapsed_ms=$elapsed")
                if (index == 1) assertTrue(sent < compressed.size / 2)
                var restored = byteArrayOf()
                assertTrue(service.load(key("abcd$index")) { input -> restored = GZIPInputStream(input).readBytes() })
                assertContentEquals(bytes, restored)
                val receivedBefore = downloaded.get()
                val downloadStarted = System.nanoTime()
                val newReader = service(proxy.url("/").toString(), project, push = false, chunks = directory)
                try {
                    assertTrue(newReader.load(key("abcd$index")) { input -> restored = GZIPInputStream(input).readBytes() })
                } finally { newReader.close() }
                assertContentEquals(bytes, restored)
                val received = downloaded.get() - receivedBefore
                println("BENCH gradle_download phase=$index legacy_bytes=${compressed.size} downloaded_bytes=$received elapsed_ms=${(System.nanoTime() - downloadStarted) / 1e6}")
                if (index == 1) assertTrue(received < compressed.size / 2)
            }
        }
    }
}
