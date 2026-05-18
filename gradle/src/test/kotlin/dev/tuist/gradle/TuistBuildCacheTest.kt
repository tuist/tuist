package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.gradle.caching.BuildCacheEntryReader
import org.gradle.caching.BuildCacheEntryWriter
import org.gradle.caching.BuildCacheException
import org.gradle.caching.BuildCacheKey
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.ZipException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TuistBuildCacheTest {

    private lateinit var mockServer: MockWebServer

    @BeforeEach
    fun setup() {
        mockServer = MockWebServer()
        mockServer.start()
    }

    @AfterEach
    fun tearDown() {
        mockServer.shutdown()
    }

    @Test
    fun `TuistBuildCache has correct default values`() {
        val cache = TuistBuildCache()

        assertNull(cache.project)
        assertEquals(false, cache.allowInsecureProtocol)
        assertEquals(false, cache.isPush)
    }

    @Test
    fun `TuistBuildCache properties can be configured`() {
        val cache = TuistBuildCache().apply {
            project = "my-account/my-project"
            allowInsecureProtocol = true
            isPush = true
        }

        assertEquals("my-account/my-project", cache.project)
        assertEquals(true, cache.allowInsecureProtocol)
        assertEquals(true, cache.isPush)
    }

    @Test
    fun `CacheConfiguration parses JSON correctly with snake_case`() {
        val json = """
            {
                "url": "https://cache.tuist.dev",
                "token": "tuist_test_token_12345",
                "account_handle": "my-account",
                "project_handle": "my-project"
            }
        """.trimIndent()

        val config = Gson().fromJson(json, CacheConfiguration::class.java)

        assertEquals("https://cache.tuist.dev", config.url)
        assertEquals("tuist_test_token_12345", config.token)
        assertEquals("my-account", config.accountHandle)
        assertEquals("my-project", config.projectHandle)
    }

    @Test
    fun `load returns true and reads content when cache hit`() {
        val cacheContent = "cached-build-output"
        mockServer.enqueue(MockResponse().setBody(cacheContent).setResponseCode(200))

        val service = createService()
        val reader = TestBuildCacheEntryReader()

        val result = service.load(TestBuildCacheKey("abc123"), reader)

        assertTrue(result)
        assertEquals(cacheContent, reader.content)

        val request = mockServer.takeRequest()
        assertEquals("GET", request.method)
        assertTrue(request.path!!.contains("/api/cache/gradle/abc123"))
        assertTrue(request.path!!.contains("account_handle=test-account"))
        assertTrue(request.path!!.contains("project_handle=test-project"))
    }

    @Test
    fun `load returns false when cache miss`() {
        mockServer.enqueue(MockResponse().setResponseCode(404))

        val service = createService()
        val reader = TestBuildCacheEntryReader()

        val result = service.load(TestBuildCacheKey("notfound"), reader)

        assertFalse(result)
        assertNull(reader.content)
    }

    @Test
    fun `load sends correct authorization header`() {
        mockServer.enqueue(MockResponse().setResponseCode(404))

        val service = createService()
        service.load(TestBuildCacheKey("key"), TestBuildCacheEntryReader())

        val request = mockServer.takeRequest()
        val authHeader = request.getHeader("Authorization")
        assertEquals("Bearer test-token", authHeader)
    }

    @Test
    fun `load throws BuildCacheException with context on server error`() {
        mockServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("upstream exploded: key corrupt")
        )

        val service = createService()

        val exception = assertThrows<BuildCacheException> {
            service.load(TestBuildCacheKey("deadbeef"), TestBuildCacheEntryReader())
        }

        val message = exception.message ?: error("BuildCacheException must not have a null message")
        assertTrue(message.contains("load"), "expected operation in message, got: $message")
        assertTrue(message.contains("deadbeef"), "expected cache key in message, got: $message")
        assertTrue(message.contains("HTTP 500"), "expected HTTP status in message, got: $message")
        assertTrue(
            message.contains("upstream exploded"),
            "expected response body snippet in message, got: $message"
        )
        assertTrue(
            message.contains("host=${mockServer.hostName}"),
            "expected host in message, got: $message"
        )
    }

    @Test
    fun `load wraps reader failures with cache key and content-length`() {
        mockServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("anything")
        )

        val service = createService()
        val reader = object : BuildCacheEntryReader {
            override fun readFrom(input: InputStream) {
                throw java.io.IOException("truncated body")
            }
        }

        val exception = assertThrows<BuildCacheException> {
            service.load(TestBuildCacheKey("abc123"), reader)
        }

        val message = exception.message ?: error("BuildCacheException must not have a null message")
        assertTrue(message.contains("abc123"), "expected cache key in message, got: $message")
        assertTrue(
            message.contains("Failed to read cache entry body"),
            "expected reader description in message, got: $message"
        )
        assertTrue(
            message.contains("truncated body"),
            "expected underlying cause in message, got: $message"
        )
        assertEquals("truncated body", exception.cause?.message)
    }

    @Test
    fun `load treats invalid compressed cache entries as cache misses`() {
        mockServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("anything")
                .addHeader("ETag", "\"bad-entry\"")
                .addHeader("Last-Modified", "Tue, 21 Apr 2026 00:47:30 GMT")
        )

        val service = createService()
        val reader = object : BuildCacheEntryReader {
            override fun readFrom(input: InputStream) {
                throw ZipException("Unexpected end of ZLIB input stream")
            }
        }

        val result = service.load(TestBuildCacheKey("corrupt-entry"), reader)

        assertFalse(result)
    }

    @Test
    fun `load treats truncated compressed cache entries as cache misses`() {
        mockServer.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("anything")
                .addHeader("ETag", "\"truncated-entry\"")
                .addHeader("Last-Modified", "Tue, 21 Apr 2026 00:47:30 GMT")
        )

        val service = createService()
        val reader = object : BuildCacheEntryReader {
            override fun readFrom(input: InputStream) {
                throw EOFException("Unexpected end of ZLIB input stream")
            }
        }

        val result = service.load(TestBuildCacheKey("truncated-entry"), reader)

        assertFalse(result)
    }

    @Test
    fun `store throws BuildCacheException with context on server error`() {
        mockServer.enqueue(
            MockResponse()
                .setResponseCode(503)
                .setBody("cache unavailable")
        )

        val service = createService(isPushEnabled = true)

        val exception = assertThrows<BuildCacheException> {
            service.store(TestBuildCacheKey("putkey"), TestBuildCacheEntryWriter("payload"))
        }

        val message = exception.message ?: error("BuildCacheException must not have a null message")
        assertTrue(message.contains("store"), "expected operation in message, got: $message")
        assertTrue(message.contains("putkey"), "expected cache key in message, got: $message")
        assertTrue(message.contains("HTTP 503"), "expected HTTP status in message, got: $message")
        assertTrue(
            message.contains("cache unavailable"),
            "expected response body snippet in message, got: $message"
        )
    }

    @Test
    fun `load retries with refreshed token on 401`() {
        mockServer.enqueue(MockResponse().setResponseCode(401))
        mockServer.enqueue(MockResponse().setBody("content").setResponseCode(200))

        var configCallCount = 0
        val service = createService {
            configCallCount++
            createConfig()
        }

        val reader = TestBuildCacheEntryReader()
        val result = service.load(TestBuildCacheKey("key"), reader)

        assertTrue(result)
        assertEquals("content", reader.content)
        assertEquals(2, configCallCount)
    }

    @Test
    fun `store sends PUT request with content`() {
        mockServer.enqueue(MockResponse().setResponseCode(201))

        val service = createService(isPushEnabled = true)
        val content = "build-output-to-cache"
        val writer = TestBuildCacheEntryWriter(content)

        service.store(TestBuildCacheKey("storekey"), writer)

        val request = mockServer.takeRequest()
        assertEquals("PUT", request.method)
        assertTrue(request.path!!.contains("/api/cache/gradle/storekey"))
        assertEquals("application/octet-stream", request.getHeader("Content-Type"))
        assertEquals(content, request.body.readUtf8())
    }

    @Test
    fun `store does nothing when push is disabled`() {
        val service = createService(isPushEnabled = false)

        service.store(TestBuildCacheKey("key"), TestBuildCacheEntryWriter("content"))

        assertEquals(0, mockServer.requestCount)
    }

    @Test
    fun `store retries with refreshed token on 401`() {
        mockServer.enqueue(MockResponse().setResponseCode(401))
        mockServer.enqueue(MockResponse().setResponseCode(201))

        var configCallCount = 0
        val service = createService(isPushEnabled = true) {
            configCallCount++
            createConfig()
        }

        service.store(TestBuildCacheKey("key"), TestBuildCacheEntryWriter("content"))

        assertEquals(2, mockServer.requestCount)
        assertEquals(2, configCallCount)
    }

    @Test
    fun `buildCacheUrl constructs correct URL`() {
        val config = CacheConfiguration(
            url = "http://localhost:8080",
            token = "token",
            accountHandle = "acct",
            projectHandle = "proj"
        )

        val service = createService()
        val url = service.buildCacheUrl(config, "hashkey")

        assertEquals("http", url.scheme)
        assertEquals("localhost", url.host)
        assertEquals(8080, url.port)
        assertEquals("/api/cache/gradle/hashkey", url.path)
        assertEquals("account_handle=acct&project_handle=proj", url.query)
    }

    @Test
    fun `buildCacheUrl handles trailing slash in base URL`() {
        val config = CacheConfiguration(
            url = "http://localhost:8080/",
            token = "token",
            accountHandle = "acct",
            projectHandle = "proj"
        )

        val service = createService()
        val url = service.buildCacheUrl(config, "key")

        assertEquals("/api/cache/gradle/key", url.path)
    }

    private fun createConfig() = CacheConfiguration(
        url = mockServer.url("/").toString().trimEnd('/'),
        token = "test-token",
        accountHandle = "test-account",
        projectHandle = "test-project"
    )

    private fun createService(
        isPushEnabled: Boolean = true,
        configProvider: (Boolean) -> CacheConfiguration = { createConfig() }
    ): TuistBuildCacheService {
        val httpClient = TuistHttpClient(
            configurationProvider = object : ConfigurationProvider {
                override fun getConfiguration(forceRefresh: Boolean): CacheConfiguration =
                    configProvider(forceRefresh)
            }
        )
        return TuistBuildCacheService(
            httpClient = httpClient,
            isPushEnabled = isPushEnabled
        )
    }

    private class TestBuildCacheKey(private val hash: String) : BuildCacheKey {
        override fun getHashCode(): String = hash
        override fun toByteArray(): ByteArray = hash.toByteArray()
    }

    private class TestBuildCacheEntryReader : BuildCacheEntryReader {
        var content: String? = null

        override fun readFrom(input: InputStream) {
            content = input.bufferedReader().readText()
        }
    }

    private class TestBuildCacheEntryWriter(private val content: String) : BuildCacheEntryWriter {
        override fun writeTo(output: OutputStream) {
            output.write(content.toByteArray())
        }

        override fun getSize(): Long = content.length.toLong()
    }
}
