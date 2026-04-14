package dev.tuist.gradle

import org.gradle.api.provider.Property

/**
 * Shared Gradle managed-parameter boundary for proxy configuration.
 *
 * Build services cannot carry the sealed [Proxy] directly, so they exchange a
 * serialized declarative form and rehydrate it at execution time.
 */
interface TuistProxyParameters {
    val proxyConfiguration: Property<String>
}

internal fun TuistProxyParameters.setProxyConfiguration(proxy: Proxy) {
    proxyConfiguration.set(proxy.toParameterValue())
}

internal fun TuistProxyParameters.toProxy(): Proxy =
    Proxy.fromParameterValue(proxyConfiguration.orNull)
