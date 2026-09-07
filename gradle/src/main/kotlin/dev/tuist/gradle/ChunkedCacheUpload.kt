package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.JsonObject
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap

internal class ChunkedCacheUpload(private val client: TuistHttpClient, private val chunkDirectory: File? = null) {
    private val gson = Gson()
    private data class Capability(val supported: Boolean, val downloads: Boolean, val expires: Long)
    private val capabilities = ConcurrentHashMap<String, Capability>()

    fun supported(config: CacheConfiguration): Boolean {
        val key = endpointKey(config)
        capabilities[key]?.takeIf { it.expires > System.currentTimeMillis() }?.let { return it.supported }
        var downloads = false
        val supported = try {
            val response = request(config, "capabilities", "GET")
            val body = if (response.first == 200) gson.fromJson(response.second, JsonObject::class.java) else null
            downloads = body?.get("download_version")?.asInt == 1
            body != null && body["version"]?.asInt == 1 && body["algorithm"]?.asString == "fastcdc2020" &&
                body["average_chunk_bytes"]?.asInt == 524288 && body["seed"]?.asInt == 0 &&
                body["normalization"]?.asInt == 2 && body["minimum_blob_bytes"]?.asInt == ContentDefinedChunking.MAX_BYTES &&
                body["maximum_chunk_bytes"]?.asInt == ContentDefinedChunking.MAX_BYTES && body["maximum_chunks"]?.asInt == 16_384
        } catch (error: TokenExpiredException) {
            throw error
        } catch (_: Exception) {
            false
        }
        if (capabilities.size >= 32) capabilities.clear()
        capabilities[key] = Capability(supported, supported && downloads, System.currentTimeMillis() + 300_000)
        return supported
    }

    fun downloadsSupported(config: CacheConfiguration): Boolean = supported(config) && capabilities[endpointKey(config)]?.downloads == true

    fun disableDownloads(config: CacheConfiguration) {
        capabilities[endpointKey(config)]?.let { capabilities[endpointKey(config)] = it.copy(downloads = false) }
    }

    /** False requests a whole upload, including a mixed-version node or an eviction race. */
    fun upload(config: CacheConfiguration, cacheKey: String, file: File): Boolean {
        val prepared = ContentDefinedChunking.recompressGzip(file)
        try {
            return uploadPrepared(config, cacheKey, prepared ?: file)
        } finally {
            prepared?.delete()
        }
    }

    private fun uploadPrepared(config: CacheConfiguration, cacheKey: String, file: File): Boolean {
        val cache = chunkDirectory?.let { LocalChunkCache(it, endpointKey(config)) }
        val artifact = ContentDefinedChunking.scan(file, cache?.let { { digest, bytes -> it.put(digest, bytes) } })
        if (artifact.chunks.size < 2) return false
        val digests = artifact.chunks.map { it.digest }
        val byDigest = artifact.chunks.associateBy { it.digest }
        repeat(2) {
            val response = request(config, "missing", "POST", gson.toJson(mapOf("chunks" to digests)).toByteArray())
            if (unsupported(config, response.first)) return false
            checkStatus(response.first, 200)
            val missing = gson.fromJson(response.second, JsonObject::class.java).getAsJsonArray("missing")
                ?: throw IOException("Tuist chunk presence response is missing digests")
            require(missing.size() <= digests.size) { "Too many missing chunks" }
            val needed = missing.map { gson.fromJson(it, ContentDefinedChunking.Digest::class.java) }.toSet()
            require(needed.all(byDigest::containsKey)) { "Tuist returned an unrequested chunk" }
            RandomAccessFile(file, "r").use { input ->
                for (digest in needed) {
                    val chunk = byDigest.getValue(digest)
                    val bytes = ByteArray(digest.size.toInt())
                    input.seek(chunk.offset)
                    input.readFully(bytes)
                    require(ContentDefinedChunking.digest(bytes) == digest) { "Artifact changed during upload" }
                    val uploaded = request(config, "upload", "PUT", bytes, mapOf("hash" to digest.hash, "size" to digest.size.toString()))
                    if (unsupported(config, uploaded.first)) return false
                    checkStatus(uploaded.first, 204)
                }
            }
            val completed = request(config, "complete", "POST",
                gson.toJson(mapOf("blob" to artifact.digest, "chunks" to digests)).toByteArray(), mapOf("cache_key" to cacheKey))
            if (completed.first == 204) return true
            if (unsupported(config, completed.first)) return false
            if (completed.first != 409) checkStatus(completed.first, 204)
        }
        return false
    }

    private fun unsupported(config: CacheConfiguration, status: Int): Boolean {
        if (status !in listOf(404, 405, 501)) return false
        capabilities[endpointKey(config)] = Capability(false, false, System.currentTimeMillis() + 300_000)
        return true
    }

    fun endpointKey(config: CacheConfiguration) = "${config.url}/${config.accountHandle}/${config.projectHandle}"

    private fun checkStatus(actual: Int, expected: Int) {
        if (actual != expected) throw IOException("Tuist chunk upload failed with response $actual")
    }

    private fun request(config: CacheConfiguration, operation: String, method: String, bytes: ByteArray? = null,
                        extra: Map<String, String> = emptyMap()): Pair<Int, String> {
        val response = requestBytes(config, operation, method, bytes, extra)
        return response.first to String(response.second, StandardCharsets.UTF_8)
    }

    fun requestBytes(config: CacheConfiguration, operation: String, method: String, bytes: ByteArray? = null,
                     extra: Map<String, String> = emptyMap()): Pair<Int, ByteArray> {
        val params = mapOf("account_handle" to config.accountHandle, "project_handle" to config.projectHandle, "kind" to "gradle") + extra
        val query = params.entries.joinToString("&") { (key, value) -> "$key=${URLEncoder.encode(value, StandardCharsets.UTF_8)}" }
        val url = URI.create("${config.url.trimEnd('/')}/api/cache/chunks/$operation?$query")
        val connection = client.openConnection(url, config)
        try {
            connection.requestMethod = method
            connection.instanceFollowRedirects = false
            if (operation == "capabilities") {
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
            }
            if (bytes != null) {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.setRequestProperty("Content-Type", if (operation == "upload") "application/octet-stream" else "application/json")
                connection.outputStream.use { it.write(bytes) }
            }
            val status = connection.responseCode
            if (status == 401) throw TokenExpiredException()
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.use { it.readNBytes(2 * 1024 * 1024 + 1) } ?: byteArrayOf()
            if (body.size > 2 * 1024 * 1024) throw IOException("Tuist chunk response too large")
            return status to body
        } finally {
            connection.disconnect()
        }
    }
}
