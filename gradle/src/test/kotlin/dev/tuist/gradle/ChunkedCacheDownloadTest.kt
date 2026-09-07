package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChunkedCacheDownloadTest {
    @TempDir lateinit var directory: File
    private val capabilities = """{"version":1,"download_version":1,"algorithm":"fastcdc2020","average_chunk_bytes":524288,"seed":0,"normalization":2,"minimum_blob_bytes":2097152,"maximum_chunk_bytes":2097152,"maximum_chunks":16384}"""

    @Test fun `old and upload only servers are not asked for download manifests`() {
        for (body in listOf("{}", capabilities.replace("\"download_version\":1,", ""))) {
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setBody(body))
                val config = CacheConfiguration(server.url("/").toString(), "test", "account", "project")
                val transport = ChunkedCacheUpload(TuistHttpClient(object : ConfigurationProvider {
                    override fun getConfiguration(forceRefresh: Boolean) = config
                }))
                ChunkedCacheDownload(transport, directory).use { download -> assertNull(download.download(config, "abcd")) }
                assertEquals(1, server.requestCount)
            }
        }
    }

    @Test fun `new reader reuses persisted chunks and repairs same size corruption`() {
        val bytes = ByteArray(128 * 1024) { it.toByte() }
        val digest = ContentDefinedChunking.digest(bytes)
        val downloads = AtomicInteger()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse = when {
                    request.path!!.contains("capabilities") -> MockResponse().setBody(capabilities)
                    request.path!!.contains("manifest") -> MockResponse().setBody(Gson().toJson(mapOf("blob" to digest, "chunks" to listOf(digest))))
                    else -> { downloads.incrementAndGet(); MockResponse().setBody(okio.Buffer().write(bytes)) }
                }
            }
            val config = CacheConfiguration(server.url("/").toString(), "test", "account", "project")
            val client = TuistHttpClient(object : ConfigurationProvider { override fun getConfiguration(forceRefresh: Boolean) = config })
            val transport = ChunkedCacheUpload(client)
            repeat(2) {
                ChunkedCacheDownload(transport, directory).use { download ->
                    val file = download.download(config, "abcd")!!
                    assertContentEquals(bytes, file.readBytes())
                    file.delete()
                }
            }
            assertEquals(1, downloads.get())
            val cache = LocalChunkCache(directory, transport.endpointKey(config))
            cache.path(digest).writeBytes(ByteArray(bytes.size))
            ChunkedCacheDownload(transport, directory).use { download ->
                val file = download.download(config, "abcd")!!
                assertContentEquals(bytes, file.readBytes())
                file.delete()
            }
            assertEquals(2, downloads.get())
        }
    }

    @Test fun `invalid manifests missing chunks and corrupt bytes request legacy fallback`() {
        val bytes = byteArrayOf(1, 2, 3)
        val digest = ContentDefinedChunking.digest(bytes)
        for ((manifest, status, body) in listOf(
            "{}" to (200 to bytes),
            Gson().toJson(mapOf("blob" to digest, "chunks" to listOf(digest.copy(size = -1)))) to (200 to bytes),
            Gson().toJson(mapOf("blob" to digest, "chunks" to listOf(digest))) to (404 to bytes),
            Gson().toJson(mapOf("blob" to digest, "chunks" to listOf(digest))) to (200 to byteArrayOf(9, 9, 9)),
            Gson().toJson(mapOf("blob" to digest.copy(hash = "0".repeat(64)), "chunks" to listOf(digest))) to (200 to bytes)
        ).map { Triple(it.first, it.second.first, it.second.second) }) {
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setBody(capabilities))
                server.enqueue(MockResponse().setBody(manifest))
                server.enqueue(MockResponse().setResponseCode(status).setBody(okio.Buffer().write(body)))
                val config = CacheConfiguration(server.url("/").toString(), "test", "account", "project")
                val transport = ChunkedCacheUpload(TuistHttpClient(object : ConfigurationProvider { override fun getConfiguration(forceRefresh: Boolean) = config }))
                ChunkedCacheDownload(transport, directory).use { download -> assertNull(download.download(config, "abcd")) }
            }
        }
    }
}
