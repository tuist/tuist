package dev.tuist.gradle

import java.io.Serializable
import java.net.InetSocketAddress
import java.net.URI

/**
 * Configures the HTTP proxy the Tuist Gradle plugin uses when talking to the Tuist
 * server and related services.
 *
 * Usage in settings.gradle.kts:
 * ```
 * tuist {
 *     proxy = Proxy.EnvironmentVariable()                  // reads HTTPS_PROXY at runtime
 *     // proxy = Proxy.EnvironmentVariable("HTTP_PROXY")
 *     // proxy = Proxy.EnvironmentVariable("CORP_PROXY")
 *     // proxy = Proxy.Url("http://proxy.corp:8080")
 *     // proxy = Proxy.None                                // default — direct connections
 * }
 * ```
 */
sealed class Proxy : Serializable {
    /** No proxy. The plugin makes direct connections. */
    object None : Proxy() {
        private fun readResolve(): Any = None
    }

    /**
     * Reads the proxy URL from an environment variable.
     *
     * @property name the environment variable to read. When `null` (the default), the
     * plugin reads [DEFAULT_ENVIRONMENT_VARIABLE] at runtime — matching the convention
     * used by `curl`, `git`, and most developer tools. The actual variable name is
     * applied during resolution, not stored in the DSL declaration.
     */
    data class EnvironmentVariable(val name: String? = null) : Proxy()

    /**
     * Uses the given proxy URL directly.
     *
     * @property value the proxy URL, e.g. `http://proxy.corp:8080`. Credentials can be
     * encoded inline as `http://user:password@proxy.corp:8080`.
     */
    data class Url(val value: String) : Proxy()

    /**
     * Resolves this configuration to a `java.net.Proxy` that can be passed to OkHttp or
     * `HttpURLConnection.openConnection(Proxy)`. Returns `null` when no proxy applies —
     * either because the configuration is [None], or because the environment variable
     * the user pointed at is unset or empty.
     */
    internal fun resolve(envProvider: (String) -> String? = { System.getenv(it) }): java.net.Proxy? {
        val url = resolveUrl(envProvider) ?: return null
        return parseProxy(url)
    }

    /**
     * Resolves this configuration to a proxy URL string, or `null` if no proxy applies.
     * Used by Gradle build services that need to capture the proxy at configure time and
     * re-hydrate it inside a task execution.
     */
    internal fun resolveUrl(envProvider: (String) -> String? = { System.getenv(it) }): String? =
        when (this) {
            is None -> null
            is EnvironmentVariable -> envProvider(name ?: DEFAULT_ENVIRONMENT_VARIABLE)?.takeIf { it.isNotBlank() }
            is Url -> value
        }

    companion object {
        /** The standard environment variable `Proxy.EnvironmentVariable(null)` reads at runtime. */
        const val DEFAULT_ENVIRONMENT_VARIABLE: String = "HTTPS_PROXY"

        private fun parseProxy(url: String): java.net.Proxy? = try {
            val uri = URI(url)
            val host = uri.host ?: return null
            val port = if (uri.port != -1) {
                uri.port
            } else {
                when (uri.scheme?.lowercase()) {
                    "https" -> 443
                    "http" -> 80
                    else -> 8080
                }
            }
            java.net.Proxy(java.net.Proxy.Type.HTTP, InetSocketAddress(host, port))
        } catch (_: Exception) {
            null
        }

        /**
         * Reverse of [Proxy.resolveUrl]: given the resolved proxy URL captured at configure
         * time (or `null` when there's no proxy), return the [Proxy] to hand to HTTP clients.
         *
         * Build services serialize the resolved URL as a plain string so the sealed class
         * does not need to survive Gradle's managed parameter boundary.
         */
        internal fun fromResolvedUrl(url: String?): Proxy =
            url?.takeIf { it.isNotBlank() }?.let { Url(it) } ?: None
    }
}

internal fun resolveProxyFromParameters(url: String?): Proxy = Proxy.fromResolvedUrl(url)
