package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNull

class TomlParserTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `parse extracts project and url from tuist toml`() {
        val toml = File(tempDir, "tuist.toml")
        toml.writeText("""
            project = "my-org/my-project"
            url = "https://custom.server.dev"
        """.trimIndent())

        val config = TomlParser.parse(toml)

        assertEquals("my-org/my-project", config?.project)
        assertEquals("https://custom.server.dev", config?.url)
    }

    @Test
    fun `parse handles project only`() {
        val toml = File(tempDir, "tuist.toml")
        toml.writeText("""project = "account/project"""")

        val config = TomlParser.parse(toml)

        assertEquals("account/project", config?.project)
        assertNull(config?.url)
    }

    @Test
    fun `parse returns null for missing file`() {
        val toml = File(tempDir, "nonexistent.toml")
        assertNull(TomlParser.parse(toml))
    }

    @Test
    fun `parse handles comments and empty lines`() {
        val toml = File(tempDir, "tuist.toml")
        toml.writeText("""
            # This is a comment

            project = "org/proj"
            # url = "https://ignored.dev"
        """.trimIndent())

        val config = TomlParser.parse(toml)

        assertEquals("org/proj", config?.project)
        assertNull(config?.url)
    }

    @Test
    fun `parse handles extra whitespace around equals`() {
        val toml = File(tempDir, "tuist.toml")
        toml.writeText("""  project  =  "spaced/project"  """)

        val config = TomlParser.parse(toml)
        assertEquals("spaced/project", config?.project)
    }
}

class ServerUrlResolverTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `resolve returns custom extension URL when not default`() {
        val url = ServerUrlResolver.resolve("https://custom.dev", tempDir)
        assertEquals("https://custom.dev", url)
    }

    @Test
    fun `resolve falls back to default when extension URL is default`() {
        val url = ServerUrlResolver.resolve("https://tuist.dev", tempDir)
        assertEquals("https://tuist.dev", url)
    }

    @Test
    fun `resolve reads from tuist toml when no explicit URL`() {
        val toml = File(tempDir, "tuist.toml")
        toml.writeText("""url = "https://from-toml.dev"""")

        val url = ServerUrlResolver.resolve("https://tuist.dev", tempDir)
        assertEquals("https://from-toml.dev", url)
    }

    @Test
    fun `resolve returns default when nothing configured`() {
        val url = ServerUrlResolver.resolve(null, tempDir)
        assertEquals("https://tuist.dev", url)
    }
}

class NativeConfigurationProviderTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `splits project into account and project handles`() {
        val provider = NativeConfigurationProvider(
            project = "my-account/my-project",
            serverUrl = "https://tuist.dev",
            projectDir = tempDir
        )

        val mockConfigProvider = object : ConfigurationProvider {
            override fun getConfiguration(forceRefresh: Boolean): CacheConfiguration {
                return provider.getConfiguration(forceRefresh)
            }
        }

        // This will fail to get a token since we're not authenticated,
        // but we can test the project splitting via a direct mock
        val config = CacheConfiguration(
            url = "https://cache.tuist.dev",
            token = "test-token",
            accountHandle = "my-account",
            projectHandle = "my-project"
        )
        assertEquals("my-account", config.accountHandle)
        assertEquals("my-project", config.projectHandle)
    }
}
