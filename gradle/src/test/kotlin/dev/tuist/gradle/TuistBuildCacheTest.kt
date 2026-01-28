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
import java.io.InputStream
import java.io.OutputStream
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TuistVersionTest {

    @Test
    fun `parseVersion parses valid version strings`() {
        assertEquals(listOf(4, 31, 0), TuistVersion.parseVersion("4.31.0"))
        assertEquals(listOf(1, 0, 0), TuistVersion.parseVersion("1.0.0"))
        assertEquals(listOf(10, 20, 30), TuistVersion.parseVersion("10.20.30"))
        assertEquals(listOf(4, 31), TuistVersion.parseVersion("4.31"))
    }

    @Test
    fun `parseVersion returns null for invalid versions`() {
        assertNull(TuistVersion.parseVersion(""))
        assertNull(TuistVersion.parseVersion("abc"))
        assertNull(TuistVersion.parseVersion("1.2.abc"))
    }

    @Test
    fun `isVersionSufficient returns true for equal versions`() {
        assertTrue(TuistVersion.isVersionSufficient("4.31.0", "4.31.0"))
        assertTrue(TuistVersion.isVersionSufficient("1.0.0", "1.0.0"))
    }

    @Test
    fun `isVersionSufficient returns true for newer versions`() {
        assertTrue(TuistVersion.isVersionSufficient("4.32.0", "4.31.0"))
        assertTrue(TuistVersion.isVersionSufficient("5.0.0", "4.31.0"))
        assertTrue(TuistVersion.isVersionSufficient("4.31.1", "4.31.0"))
    }

    @Test
    fun `isVersionSufficient returns false for older versions`() {
        assertFalse(TuistVersion.isVersionSufficient("4.30.0", "4.31.0"))
        assertFalse(TuistVersion.isVersionSufficient("3.0.0", "4.31.0"))
        assertFalse(TuistVersion.isVersionSufficient("4.30.99", "4.31.0"))
    }

    @Test
    fun `isVersionSufficient handles versions with different segment counts`() {
        assertTrue(TuistVersion.isVersionSufficient("4.32", "4.31.0"))
        assertTrue(TuistVersion.isVersionSufficient("4.31.0", "4.31"))
        assertFalse(TuistVersion.isVersionSufficient("4.30", "4.31.0"))
    }

    @Test
    fun `isVersionSufficient returns false for invalid versions`() {
        assertFalse(TuistVersion.isVersionSufficient("invalid", "4.31.0"))
        assertFalse(TuistVersion.isVersionSufficient("4.31.0", "invalid"))
    }
}

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

        assertEquals("", cache.fullHandle)
        assertNull(cache.executablePath)
        assertNull(cache.executableCommand)
        assertEquals(false, cache.allowInsecureProtocol)
        assertEquals(false, cache.isPush)
    }

    @Test
    fun `TuistBuildCache properties can be configured`() {
        val cache = TuistBuildCache().apply {
            fullHandle = "my-account/my-project"
            executablePath = "/custom/path/tuist"
            allowInsecureProtocol = true
            isPush = true
        }

        assertEquals("my-account/my-project", cache.fullHandle)
        assertEquals("/custom/path/tuist", cache.executablePath)
        assertEquals(true, cache.allowInsecureProtocol)
        assertEquals(true, cache.isPush)
    }

    @Test
    fun `TuistBuildCache can be configured with executableCommand`() {
        val cache = TuistBuildCache().apply {
            fullHandle = "my-account/my-project"
            executableCommand = listOf("swift", "run", "tuist")
            isPush = true
        }

        assertEquals("my-account/my-project", cache.fullHandle)
        assertEquals(listOf("swift", "run", "tuist"), cache.executableCommand)
        assertEquals(true, cache.isPush)
    }

    @Test
    fun `TuistCacheConfiguration parses JSON correctly`() {
        val json = """
            {
                "url": "https://cache.tuist.dev",
                "token": "tuist_test_token_12345",
                "accountHandle": "my-account",
                "projectHandle": "my-project"
            }
        """.trimIndent()

        val config = Gson().fromJson(json, TuistCacheConfiguration::class.java)

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
    fun `load throws exception on server error`() {
        mockServer.enqueue(MockResponse().setResponseCode(500))

        val service = createService()

        assertThrows<BuildCacheException> {
            service.load(TestBuildCacheKey("key"), TestBuildCacheEntryReader())
        }
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
        val config = TuistCacheConfiguration(
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
        val config = TuistCacheConfiguration(
            url = "http://localhost:8080/",
            token = "token",
            accountHandle = "acct",
            projectHandle = "proj"
        )

        val service = createService()
        val url = service.buildCacheUrl(config, "key")

        assertEquals("/api/cache/gradle/key", url.path)
    }

    private fun createConfig() = TuistCacheConfiguration(
        url = mockServer.url("/").toString().trimEnd('/'),
        token = "test-token",
        accountHandle = "test-account",
        projectHandle = "test-project"
    )

    private fun createService(
        isPushEnabled: Boolean = true,
        configProvider: () -> TuistCacheConfiguration? = { createConfig() }
    ): TuistBuildCacheService {
        return TuistBuildCacheService(
            configurationProvider = ConfigurationProvider { configProvider() },
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
