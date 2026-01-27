package dev.tuist.gradle

import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals

class TuistBuildCacheServiceTest {

    @Test
    fun `buildCacheUrl constructs correct URL with simple base URL`() {
        val config = TuistCacheConfiguration(
            url = "https://cache.tuist.dev",
            token = "test-token",
            accountHandle = "my-account",
            projectHandle = "my-project"
        )

        val result = buildCacheUrl(config, "abc123def456")

        assertEquals("https", result.scheme)
        assertEquals("cache.tuist.dev", result.host)
        assertEquals("/api/cache/gradle/abc123def456", result.path)
        assertEquals("account_handle=my-account&project_handle=my-project", result.query)
    }

    @Test
    fun `buildCacheUrl constructs correct URL with trailing slash in base URL`() {
        val config = TuistCacheConfiguration(
            url = "https://cache.tuist.dev/",
            token = "test-token",
            accountHandle = "my-account",
            projectHandle = "my-project"
        )

        val result = buildCacheUrl(config, "abc123")

        assertEquals("/api/cache/gradle/abc123", result.path)
    }

    @Test
    fun `buildCacheUrl constructs correct URL with port`() {
        val config = TuistCacheConfiguration(
            url = "http://localhost:8181",
            token = "test-token",
            accountHandle = "tuist",
            projectHandle = "gradle"
        )

        val result = buildCacheUrl(config, "hash123")

        assertEquals("http", result.scheme)
        assertEquals("localhost", result.host)
        assertEquals(8181, result.port)
        assertEquals("/api/cache/gradle/hash123", result.path)
        assertEquals("account_handle=tuist&project_handle=gradle", result.query)
    }

    @Test
    fun `buildCacheUrl constructs correct URL with existing path in base URL`() {
        val config = TuistCacheConfiguration(
            url = "https://api.example.com/v1",
            token = "test-token",
            accountHandle = "org",
            projectHandle = "repo"
        )

        val result = buildCacheUrl(config, "cachekey")

        assertEquals("/v1/api/cache/gradle/cachekey", result.path)
    }

    @Test
    fun `buildCacheUrl handles special characters in handles`() {
        val config = TuistCacheConfiguration(
            url = "https://cache.tuist.dev",
            token = "test-token",
            accountHandle = "my-account",
            projectHandle = "my-project"
        )

        val result = buildCacheUrl(config, "key-with-dashes_and_underscores")

        assertEquals("/api/cache/gradle/key-with-dashes_and_underscores", result.path)
    }

    private fun buildCacheUrl(config: TuistCacheConfiguration, cacheKey: String): URI {
        val baseUri = URI.create(config.url.trimEnd('/'))
        return URI(
            baseUri.scheme,
            baseUri.userInfo,
            baseUri.host,
            baseUri.port,
            "${baseUri.path}/api/cache/gradle/$cacheKey",
            "account_handle=${config.accountHandle}&project_handle=${config.projectHandle}",
            null
        )
    }
}
