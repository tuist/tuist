package dev.tuist.gradle

import com.google.gson.JsonParser
import okhttp3.Request
import java.io.File
import java.net.URI
import java.util.Locale

/** Report publishing must not depend on authenticated cache-endpoint discovery. */
internal class ReportConfigurationProvider(
    private val project: String?,
    private val serverUrl: String,
    private val projectDir: File,
    private val httpClients: TuistHttpClients,
    private val networkPublishingAvailable: (URI) -> Boolean = { uri ->
        val request = Request.Builder()
            .url(uri.resolve("/.well-known/tuist.json").toString())
            .header("Accept", "application/json")
            .build()
        httpClients.okHttp.newBuilder()
            .followRedirects(false)
            .followSslRedirects(false)
            .callTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .build().newCall(request).execute().use { response ->
                response.code == 200 && response.body?.charStream()?.use { reader ->
                    val value = JsonParser.parseReader(reader).asJsonObject["network_trusted_report_publishing"]
                    value?.isJsonPrimitive == true && value.asJsonPrimitive.isBoolean && value.asBoolean
                } == true
            }
    },
    private val tokenProviderFactory: (URI) -> TokenProvider = { TokenProvider(it, httpClients = httpClients) },
    private val serverUrlResolver: (String, File) -> String = ServerUrlResolver::resolve
) : ConfigurationProvider {
    private val resolvedUrl by lazy { URI(serverUrlResolver(serverUrl, projectDir)) }
    private val tokenProvider by lazy { tokenProviderFactory(resolvedUrl) }

    override fun getConfiguration(forceRefresh: Boolean): CacheConfiguration {
        val fullName = project?.takeIf(String::isNotBlank)
            ?: ServerUrlResolver.findTomlFile(projectDir)?.let { TomlParser.parse(it)?.project }
            ?: throw IllegalStateException("No Tuist project configured for report publishing.")
        val handle = ProjectHandle.parse(fullName)
        require(handle.accountHandle.isNotBlank() && handle.projectHandle.isNotBlank()) { "Expected account/project." }
        val token = tokenProvider.getOptionalToken(forceRefresh)
        val host = resolvedUrl.host?.trimEnd('.')?.lowercase(Locale.ROOT)
        check(token != null || (resolvedUrl.scheme in setOf("http", "https") && resolvedUrl.userInfo == null && host != null)) {
            "Credential-free publishing requires a configured self-hosted Tuist server URL."
        }
        if (token == null && (host in hostedHosts || host?.endsWith(".tuist.dev") == true || host?.endsWith(".tuist.io") == true)) {
            throw TokenProvider.NotAuthenticatedException(resolvedUrl)
        }
        check(token != null || networkPublishingAvailable(resolvedUrl)) {
            "This Tuist server requires authentication to publish reports. Sign in to continue."
        }
        return CacheConfiguration(resolvedUrl.toString(), token ?: "", handle.accountHandle, handle.projectHandle)
    }

    private companion object {
        val hostedHosts = setOf("tuist.dev", "www.tuist.dev", "canary.tuist.dev", "staging.tuist.dev", "cloud.tuist.io", "cloud.tuist.dev", "tuist.io")
    }
}
