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
 *     proxy = Proxy.StandardEnvironment      // reads HTTPS_PROXY then HTTP_PROXY
 *     // proxy = Proxy.EnvironmentVariable("CORP_PROXY")
 *     // proxy = Proxy.Url("http://proxy.corp:8080")
 *     // proxy = Proxy.None                  // default — direct connections
 * }
 * ```
 */
sealed class Proxy : Serializable {
    /** No proxy. The plugin makes direct connections. */
    object None : Proxy() {
        private fun readResolve(): Any = None
        private const val serialVersionUID = 1L
    }

    /**
     * Reads the proxy URL from the standard `HTTPS_PROXY` environment variable,
     * falling back to `HTTP_PROXY`. Both the uppercase and lowercase forms are checked.
     */
    object StandardEnvironment : Proxy() {
        private fun readResolve(): Any = StandardEnvironment
        private const val serialVersionUID = 1L
    }

    /**
     * Reads the proxy URL from a custom environment variable.
     *
     * @property name the environment variable to read.
     */
    data class EnvironmentVariable(val name: String) : Proxy() {
        companion object {
            private const val serialVersionUID = 1L
        }
    }

    /**
     * Uses the given proxy URL directly.
     *
     * @property value the proxy URL, e.g. `http://proxy.corp:8080`. Credentials can be
     * encoded inline as `http://user:password@proxy.corp:8080`.
     */
    data class Url(val value: String) : Proxy() {
        companion object {
            private const val serialVersionUID = 1L
        }
    }

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
            is StandardEnvironment -> firstNonBlank(
                envProvider("HTTPS_PROXY"),
                envProvider("https_proxy"),
                envProvider("HTTP_PROXY"),
                envProvider("http_proxy")
            )
            is EnvironmentVariable -> envProvider(name)?.takeIf { it.isNotBlank() }
            is Url -> value
        }

    companion object {
        private const val serialVersionUID = 1L

        private fun firstNonBlank(vararg values: String?): String? =
            values.firstOrNull { !it.isNullOrBlank() }

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
