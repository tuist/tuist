package dev.tuist.gradle

import com.google.gson.Gson
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.Executors

internal class ChunkedCacheDownload(private val transport: ChunkedCacheUpload, private val directory: File) : AutoCloseable {
    private data class Manifest(val blob: ContentDefinedChunking.Digest, val chunks: List<ContentDefinedChunking.Digest>)
    private val workers = Executors.newFixedThreadPool(4)

    fun download(config: CacheConfiguration, key: String): File? {
        if (!transport.downloadsSupported(config)) return null
        val response = transport.requestBytes(config, "manifest", "GET", extra = mapOf("cache_key" to key))
        if (response.first in listOf(404, 405, 501)) {
            if (response.first != 404) transport.disableDownloads(config)
            return null
        }
        checkStatus(response.first)
        val manifest = try { Gson().fromJson(String(response.second, Charsets.UTF_8), Manifest::class.java) } catch (_: Exception) { return null }
        if (!valid(manifest)) return null
        val cache = LocalChunkCache(directory, transport.endpointKey(config))
        val output = Files.createTempFile("tuist-cache-download-", ".bin").toFile()
        var handedOff = false
        try {
            val hasher = MessageDigest.getInstance("SHA-256")
            output.outputStream().use { stream ->
                for (group in manifest.chunks.chunked(4)) {
                    val futures = group.map { digest -> workers.submit<ByteArray?> {
                        cache.get(digest) ?: run {
                            val chunk = transport.requestBytes(config, "download", "GET", extra = mapOf("hash" to digest.hash, "size" to digest.size.toString()))
                            if (chunk.first in listOf(404, 405, 501)) {
                                if (chunk.first != 404) transport.disableDownloads(config)
                                return@submit null
                            }
                            checkStatus(chunk.first)
                            if (ContentDefinedChunking.digest(chunk.second) != digest) return@submit null
                            cache.put(digest, chunk.second)
                            chunk.second
                        }
                    } }
                    try {
                        for (future in futures) {
                            val bytes = try { future.get() } catch (error: java.util.concurrent.ExecutionException) { throw error.cause ?: error }
                                ?: return null
                            hasher.update(bytes)
                            stream.write(bytes)
                        }
                    } finally { futures.forEach { it.cancel(true) } }
                }
            }
            val digest = hasher.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
            if (output.length() != manifest.blob.size || digest != manifest.blob.hash) return null
            return output.also { handedOff = true }
        } finally {
            if (!handedOff) output.delete()
        }
    }

    private fun valid(manifest: Manifest?): Boolean = try {
        manifest != null && validDigest(manifest.blob, 100L * 1024 * 1024) &&
            manifest.chunks.size in 1..16_384 && manifest.chunks.all { validDigest(it, ContentDefinedChunking.MAX_BYTES.toLong()) } &&
            manifest.chunks.sumOf { it.size } == manifest.blob.size
    } catch (_: Exception) { false }

    private fun validDigest(digest: ContentDefinedChunking.Digest, maximum: Long) =
        digest.size in 1..maximum && digest.hash.matches(Regex("[a-f0-9]{64}"))

    private fun checkStatus(status: Int) {
        if (status != 200) throw IOException("Tuist chunk download failed with response $status")
    }

    override fun close() { workers.shutdownNow() }
}
