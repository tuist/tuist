package dev.tuist.gradle

import okhttp3.Interceptor
import okhttp3.Response
import java.util.Properties

/**
 * The version of this plugin, sent on every request so the server can tell plugin releases apart:
 * releases from 0.15.0 on no longer send the `kura` client feature flag and are always routed to Kura.
 */
object PluginVersion {
    const val HEADER_NAME = "x-tuist-gradle-plugin-version"

    /** Written into `plugin.properties` when the plugin is built. */
    val current: String? by lazy {
        PluginVersion::class.java.getResourceAsStream("plugin.properties")?.use { stream ->
            Properties().apply { load(stream) }.getProperty("version")
        }
    }
}

class PluginVersionInterceptor(private val version: String?) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val version = version ?: return chain.proceed(chain.request())
        return chain.proceed(chain.request().newBuilder().header(PluginVersion.HEADER_NAME, version).build())
    }
}
