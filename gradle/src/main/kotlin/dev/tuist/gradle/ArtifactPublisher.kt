package dev.tuist.gradle

import com.google.gson.GsonBuilder
import com.google.gson.JsonElement
import com.google.gson.JsonParser
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.net.URI
import java.security.MessageDigest

/** Tuist's immutable artifact protocol keeps upload side effects outside Gradle's build cache. */
internal class ArtifactPublisher(
    configurationProvider: ConfigurationProvider,
    httpClients: TuistHttpClients
) {
    private val authenticated = TuistHttpClient(configurationProvider, httpClients)
    // A dropped POST has an unknown outcome: never silently resend it, including OkHttp's own retries.
    private val client = httpClients.okHttp.newBuilder()
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()

    fun publish(
        product: File, metadata: Map<String, Any?>, target: String, track: String?,
        productMediaType: String = "application/vnd.android.package-archive",
        productInterface: String = "dev.once.android-install.v1"
    ): String {
        if (productInterface == "dev.once.android-install.v1") {
            listOf("application_id", "version_code", "version_name").forEach { field ->
                val value = metadata[field]
                require(value == null || (value is String && value.toByteArray(Charsets.UTF_8).size <= 255 && '\u0000' !in value)) {
                    "Android metadata is not eligible for a preview: $field"
                }
            }
            require((metadata["application_id"] as? String)?.isNotBlank() == true)
        }
        val blobs = linkedMapOf<String, RequestBody>()
        fun descriptor(digest: String, size: Long, media: String) =
            mapOf("digest" to digest, "size_bytes" to size, "media_type" to media)
        fun document(value: Any, media: String): Map<String, Any> {
            val bytes = canonical(value)
            val digest = "sha256:" + hexDigest(bytes)
            blobs[digest] = bytes.toRequestBody("application/octet-stream".toMediaType())
            return descriptor(digest, bytes.size.toLong(), media)
        }
        val productDigest = product.inputStream().use { input ->
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val size = input.read(buffer)
                if (size < 0) break
                digest.update(buffer, 0, size)
            }
            "sha256:" + hex(digest.digest())
        }
        blobs[productDigest] = product.asRequestBody("application/octet-stream".toMediaType())
        val artifact = document(mapOf(
            "schema" to "once.artifact.v1",
            "payloads" to mapOf(
                "product" to descriptor(productDigest, product.length(), productMediaType),
                "metadata" to document(metadata, "application/json")
            ),
            "interfaces" to mapOf(productInterface to mapOf(
                "payload" to "product", "spec" to mapOf("metadata_payload" to "metadata")
            ))
        ), "application/vnd.once.artifact.v1+json")
        val root = document(mapOf(
            "schema" to "once.artifact_set.v1",
            "members" to mapOf("product" to mapOf("artifact" to artifact, "selectors" to emptyMap<String, String>()))
        ), "application/vnd.once.artifact-set.v1+json")
        val intent = canonical(mapOf(
            "schema" to "once.publication_intent.v1", "target" to target,
            "root" to root, "track" to track, "revision" to null
        ))
        val key = "sha256:" + hexDigest(intent)
        fun request(method: String, path: String, body: RequestBody? = null): JsonElement? = authenticated.execute { config ->
            val uri = URI(config.url)
            require(uri.scheme == "https" || (uri.scheme == "http" && uri.host in setOf("localhost", "127.0.0.1", "::1"))) {
                "Preview publication requires HTTPS (HTTP is allowed for loopback development)."
            }
            require(uri.userInfo == null && uri.rawQuery == null && uri.rawFragment == null && uri.path in listOf("", "/"))
            val handle = Regex("[a-zA-Z0-9_-]+")
            require(handle.matches(config.accountHandle) && handle.matches(config.projectHandle)) { "Expected account/project." }
            val base = config.url.trimEnd('/') + "/api/projects/${config.accountHandle}/${config.projectHandle}/artifacts"
            val perform = {
                val request = Request.Builder().url(base + path)
                    .header("Authorization", "Bearer ${config.token}")
                    .method(method, body).build()
                client.newCall(request).execute().use { response ->
                    if (response.code == 401) throw TokenExpiredException()
                    if (method == "GET" && response.code == 404) null
                    else {
                        if (!response.isSuccessful) throw TuistRetry.statusFailure(response.code, response.header("Retry-After")) {
                            IllegalStateException("Artifact service rejected $method (HTTP ${response.code}); publication is not confirmed.")
                        }
                        val bytes = response.body?.byteStream()?.readNBytes(1_048_577)
                        check(bytes != null && bytes.size <= 1_048_576) { "Invalid artifact service response." }
                        val value = JsonParser.parseString(bytes.toString(Charsets.UTF_8))
                        check(method != "GET" || !value.isJsonNull) { "Artifact lookup did not confirm publication." }
                        value
                    }
                }
            }
            // GETs are replay-safe. Publication POSTs deliberately bypass retries.
            if (method == "GET") authenticated.retrying("artifact lookup", replaySafe = true, perform) else perform()
        }
        val capabilities = request("GET", "/")?.asJsonObject
        check(capabilities?.get("schema")?.asString == "once.publication_service.v1") { "Server does not support artifact publication." }
        val destination = capabilities?.get("destination")
        check(destination != null && !destination.isJsonNull)
        val path = "/publications/$key"
        fun confirm(receipt: JsonElement?) {
            check(receipt?.isJsonObject == true && receipt.asJsonObject.let {
                it["schema"]?.asString == "once.publication_receipt.v1" && it["key"]?.asString == key &&
                    it["root"] == JsonParser.parseString(canonical(root).toString(Charsets.UTF_8)) && it["destination"] == destination
            }) { "Invalid receipt; publication is not confirmed." }
        }
        val existing = request("GET", path)
        if (existing != null) {
            confirm(existing)
            return "Already published $key"
        }
        blobs.forEach { (digest, body) -> request("POST", "$path/content/$digest", body) }
        confirm(request("POST", path, intent.toRequestBody("application/json".toMediaType())))
        return "Published $key"
    }

    companion object {
        private val gson = GsonBuilder().disableHtmlEscaping().serializeNulls().create()
        private fun canonicalJson(value: Any?): String = when (value) {
            is Map<*, *> -> value.entries.sortedBy { it.key.toString() }.joinToString(",", "{", "}") {
                canonicalJson(it.key.toString()) + ":" + canonicalJson(it.value)
            }
            is List<*> -> value.joinToString(",", "[", "]", transform = ::canonicalJson)
            // Gson escapes U+2028/2029 for JavaScript embedding, but the publication
            // identity uses ordinary JSON with literal UTF-8, as the server and Once do.
            is String -> buildString {
                append('"')
                value.forEach { char ->
                    append(when (char) {
                        '"' -> "\\\""
                        '\\' -> "\\\\"
                        '\b' -> "\\b"
                        '\u000c' -> "\\f"
                        '\n' -> "\\n"
                        '\r' -> "\\r"
                        '\t' -> "\\t"
                        else -> if (char < ' ') "\\u%04x".format(char.code) else char.toString()
                    })
                }
                append('"')
            }
            else -> gson.toJson(value)
        }
        private fun canonical(value: Any): ByteArray = canonicalJson(value).toByteArray(Charsets.UTF_8)
        private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
        fun hexDigest(bytes: ByteArray) = hex(MessageDigest.getInstance("SHA-256").digest(bytes))
    }
}
