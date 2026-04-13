package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals

class ProxyResolverTest {

    @TempDir
    lateinit var projectDir: File

    @Test
    fun `extension proxy wins over tuist toml`() {
        writeToml(
            """
            project = "org/project"

            [proxy]
            url = "http://toml.corp:8080"
            """.trimIndent()
        )

        val resolved = ProxyResolver.resolve(
            extensionProxy = Proxy.Url("http://dsl.corp:9090"),
            projectDir = projectDir
        )

        assertEquals(Proxy.Url("http://dsl.corp:9090"), resolved)
    }

    @Test
    fun `falls back to toml proxy url when extension is None`() {
        writeToml(
            """
            project = "org/project"

            [proxy]
            url = "http://toml.corp:8080"
            """.trimIndent()
        )

        val resolved = ProxyResolver.resolve(Proxy.None, projectDir)

        assertEquals(Proxy.Url("http://toml.corp:8080"), resolved)
    }

    @Test
    fun `falls back to toml proxy environment variable when extension is None`() {
        writeToml(
            """
            project = "org/project"

            [proxy]
            environment_variable = "CORP_PROXY"
            """.trimIndent()
        )

        val resolved = ProxyResolver.resolve(Proxy.None, projectDir)

        assertEquals(Proxy.EnvironmentVariable("CORP_PROXY"), resolved)
    }

    @Test
    fun `returns None when neither extension nor toml are set`() {
        writeToml("""project = "org/project"""")

        val resolved = ProxyResolver.resolve(Proxy.None, projectDir)

        assertEquals(Proxy.None, resolved)
    }

    @Test
    fun `returns None when there is no toml file at all`() {
        val resolved = ProxyResolver.resolve(Proxy.None, projectDir)

        assertEquals(Proxy.None, resolved)
    }

    @Test
    fun `returns None when projectDir is null`() {
        val resolved = ProxyResolver.resolve(Proxy.None, null)

        assertEquals(Proxy.None, resolved)
    }

    private fun writeToml(contents: String) {
        File(projectDir, "tuist.toml").writeText(contents)
    }
}
