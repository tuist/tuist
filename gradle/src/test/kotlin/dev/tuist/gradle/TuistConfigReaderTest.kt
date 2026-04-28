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

            [network]
            proxy = false
        """.trimIndent())

        val config = TomlParser.parse(toml)

        assertEquals("my-org/my-project", config?.project)
        assertEquals("https://custom.server.dev", config?.url)
        assertEquals(false, config?.network?.proxy)
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

    @Test
    fun `parse handles network proxy only`() {
        val toml = File(tempDir, "tuist.toml")
        toml.writeText("""
            [network]
            proxy = false
        """.trimIndent())

        val config = TomlParser.parse(toml)

        assertEquals(false, config?.network?.proxy)
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

class ProjectHandleTest {

    @Test
    fun `parse splits into account and project`() {
        val handle = ProjectHandle.parse("my-account/my-project")
        assertEquals("my-account", handle.accountHandle)
        assertEquals("my-project", handle.projectHandle)
    }

    @Test
    fun `parse single-segment uses empty project`() {
        val handle = ProjectHandle.parse("my-account")
        assertEquals("my-account", handle.accountHandle)
        assertEquals("", handle.projectHandle)
    }
}

class ServerUrlResolverFindTomlTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `findTomlFile traverses up directory tree`() {
        val nested = File(tempDir, "a/b/c")
        nested.mkdirs()
        val toml = File(tempDir, "tuist.toml")
        toml.writeText("""project = "org/proj"""")

        val found = ServerUrlResolver.findTomlFile(nested)
        assertEquals(toml.canonicalPath, found?.canonicalPath)
    }

    @Test
    fun `findTomlFile returns null when no toml exists`() {
        val nested = File(tempDir, "empty/nested")
        nested.mkdirs()

        assertNull(ServerUrlResolver.findTomlFile(nested))
    }
}

class EnvironmentProxyResolverTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `resolve returns extension value when set`() {
        File(tempDir, "tuist.toml").writeText("""
            [network]
            proxy = false
        """.trimIndent())

        val result = EnvironmentProxyResolver.resolve(extensionProxy = true, projectDir = tempDir)

        assertEquals(true, result)
    }

    @Test
    fun `resolve reads from tuist toml when extension value is not set`() {
        File(tempDir, "tuist.toml").writeText("""
            [network]
            proxy = false
        """.trimIndent())

        val result = EnvironmentProxyResolver.resolve(extensionProxy = null, projectDir = tempDir)

        assertEquals(false, result)
    }

    @Test
    fun `resolve defaults to true when nothing is configured`() {
        val result = EnvironmentProxyResolver.resolve(extensionProxy = null, projectDir = tempDir)

        assertEquals(true, result)
    }
}
