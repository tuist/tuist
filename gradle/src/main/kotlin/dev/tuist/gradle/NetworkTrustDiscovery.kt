package dev.tuist.gradle

import com.google.gson.JsonParser
import okhttp3.Request
import java.net.URI
import java.util.Locale
import java.util.concurrent.TimeUnit

internal object NetworkTrustDiscovery {
    fun isSelfHosted(uri: URI): Boolean {
        val host = uri.host?.trimEnd('.')?.lowercase(Locale.ROOT) ?: return false
        return uri.scheme in setOf("http", "https") && uri.userInfo == null &&
            host !in setOf("tuist.dev", "tuist.io") &&
            !host.endsWith(".tuist.dev") && !host.endsWith(".tuist.io")
    }

    fun available(uri: URI, capability: String, httpClients: TuistHttpClients): Boolean {
        if (!isSelfHosted(uri)) return false
        return get(uri.resolve("/.well-known/tuist.json"), httpClients) { body ->
            val value = JsonParser.parseString(body).asJsonObject[capability]
            value?.isJsonPrimitive == true && value.asJsonPrimitive.isBoolean && value.asBoolean
        }
    }

    fun <T> get(uri: URI, httpClients: TuistHttpClients, decode: (String) -> T): T {
        val request = Request.Builder().url(uri.toString()).header("Accept", "application/json").build()
        return TuistRetry.run("Discovering network-trusted cache configuration", true, httpClients.retryPolicy) {
            httpClients.okHttp.newBuilder()
                .followRedirects(false).followSslRedirects(false)
                .callTimeout(10, TimeUnit.SECONDS).build().newCall(request).execute().use { response ->
                    if (response.code != 200) throw TuistRetry.statusFailure(response.code, response.header("Retry-After")) {
                        IllegalStateException("Tuist discovery failed with status ${response.code}.")
                    }
                    decode(checkNotNull(response.body).string())
                }
        }
    }
}
