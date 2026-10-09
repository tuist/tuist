package dev.tuist.gradle

import java.io.File
import java.net.URI
import java.util.Locale

/** Report publishing must not depend on authenticated cache-endpoint discovery. */
internal class ReportConfigurationProvider(
    private val project: String?,
    private val serverUrl: String,
    private val projectDir: File,
    private val httpClients: TuistHttpClients,
    private val allowNetworkTrustedPublishing: Boolean = false,
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
        val token = if (allowNetworkTrustedPublishing) tokenProvider.getOptionalToken(forceRefresh)
            else tokenProvider.getToken(forceRefresh)
        val host = resolvedUrl.host?.trimEnd('.')?.lowercase(Locale.ROOT)
        check(token != null || (host != null && host !in hostedHosts && !host.endsWith(".tuist.dev"))) {
            "Credential-free publishing requires a configured self-hosted Tuist server URL."
        }
        return CacheConfiguration(resolvedUrl.toString(), token ?: "", handle.accountHandle, handle.projectHandle)
    }

    private companion object {
        val hostedHosts = setOf("tuist.dev", "www.tuist.dev", "canary.tuist.dev", "staging.tuist.dev", "cloud.tuist.io")
    }
}
