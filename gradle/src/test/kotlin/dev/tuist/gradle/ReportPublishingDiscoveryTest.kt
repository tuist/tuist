package dev.tuist.gradle

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class ReportPublishingDiscoveryTest {
    @TempDir lateinit var directory: File

    private fun provider(url: String, token: String? = null) = ReportConfigurationProvider(
        project = "acme/widgets",
        serverUrl = url,
        projectDir = directory,
        httpClients = TuistHttpClients(useEnvironmentProxy = false),
        tokenProviderFactory = { uri ->
            TokenProvider(
                uri,
                credentialStore = CredentialStore(File(directory, "credentials")),
                envProvider = { key -> if (key == "TUIST_TOKEN") token else null },
                tokenCacheFactory = { CachedValueStore() }
            )
        },
        serverUrlResolver = { resolved, _ -> resolved }
    )

    @Test fun `discovers credential-free reporting without client configuration`() {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("{\"network_trusted_report_publishing\":true,\"future\":{\"version\":2,\"capabilities\":[\"unknown\"]}}"))
            val config = provider(server.url("/").toString()).getConfiguration()
            assertEquals("", config.token)
            val request = server.takeRequest()
            assertEquals("GET", request.method)
            assertEquals("/.well-known/tuist.json", request.path)
            assertNull(request.getHeader("Authorization"))
            assertNull(request.getHeader("x-tuist-actor-id"))
        }
    }

    @Test fun `disabled old and malformed servers require authentication`() {
        MockWebServer().use { server ->
            server.start()
            for ((status, body) in listOf(
                200 to "{\"network_trusted_report_publishing\":false}",
                200 to "{\"network_trusted_report_publishing\":\"true\"}",
                200 to "{\"network_trusted_report_publishing\":null}",
                200 to "{\"network_trusted_report_publishing\":{\"enabled\":true}}",
                200 to "[]",
                200 to "{}",
                200 to "not json",
                404 to "{}",
                503 to "{}"
            )) {
                server.enqueue(MockResponse().setResponseCode(status).setBody(body))
                assertFailsWith<Exception> { provider(server.url("/").toString()).getConfiguration() }
                assertEquals("/.well-known/tuist.json", server.takeRequest().path)
            }
        }
    }

    @Test fun `discovery does not follow redirects`() {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "/other"))
            assertFailsWith<IllegalStateException> { provider(server.url("/").toString()).getConfiguration() }
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun `present credentials are used without discovery and blank credentials fail closed`() {
        MockWebServer().use { server ->
            server.start()
            val url = server.url("/").toString()
            assertEquals("existing-token", provider(url, "existing-token").getConfiguration().token)
            assertFailsWith<Exception> { provider(url, "").getConfiguration() }
            assertEquals(0, server.requestCount)
        }
    }
}
