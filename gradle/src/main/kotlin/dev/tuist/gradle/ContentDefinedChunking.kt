package dev.tuist.gradle

import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/** FastCDC 2020, normalization 2, 512 KiB average, seed 0.
 * Matches https://github.com/bazelbuild/remote-apis/blob/main/build/bazel/remote/execution/v2/remote_execution.proto
 */
internal object ContentDefinedChunking {
    private class SizeLimitExceeded : java.io.IOException("Chunking size limit exceeded")
    const val MAX_BYTES = 2 * 1024 * 1024
    private const val MIN_BYTES = 128 * 1024
    private const val AVERAGE_BYTES = 512 * 1024
    private val gear = LongArray(256) { value ->
        val digest = MessageDigest.getInstance("MD5").digest(ByteArray(64) { value.toByte() })
        digest.take(8).fold(0L) { result, byte -> (result shl 8) or (byte.toLong() and 255) }
    }

    data class Digest(val hash: String, val size: Long)
    data class Chunk(val digest: Digest, val offset: Long)
    data class Artifact(val digest: Digest, val chunks: List<Chunk>)

    fun digest(bytes: ByteArray, count: Int = bytes.size): Digest {
        val hasher = MessageDigest.getInstance("SHA-256")
        hasher.update(bytes, 0, count)
        return Digest(hex(hasher.digest()), count.toLong())
    }

    fun cut(bytes: ByteArray, count: Int): Int {
        if (count <= MIN_BYTES) return count
        val end = minOf(count, MAX_BYTES)
        val center = minOf(end, AVERAGE_BYTES)
        var index = MIN_BYTES / 2
        var hash = 0L
        while (index < end / 2) {
            val offset = index * 2
            val mask = if (offset < center / 2 * 2) 0x0000d91767537000L else 0x0000d90703537000L
            hash = (hash shl 2) + (gear[bytes[offset].toInt() and 255] shl 1)
            if ((hash and (mask shl 1)) == 0L) return offset
            hash += gear[bytes[offset + 1].toInt() and 255]
            if ((hash and mask) == 0L) return offset + 1
            index++
        }
        return end
    }

    fun scan(file: File): Artifact = file.inputStream().use(::scan)

    fun scan(input: InputStream): Artifact {
        val hasher = MessageDigest.getInstance("SHA-256")
        val chunks = mutableListOf<Chunk>()
        var offset = 0L
        forEachChunk(input) { buffer, count ->
            hasher.update(buffer, 0, count)
            chunks.add(Chunk(digest(buffer, count), offset))
            require(chunks.size <= 16_384) { "Too many artifact chunks" }
            offset += count
        }
        return Artifact(Digest(hex(hasher.digest()), offset), chunks)
    }

    /** Concatenated gzip members preserve Gradle's unpacked archive byte for byte. */
    fun recompressGzip(file: File): File? {
        val gzip = file.inputStream().use { it.read() == 0x1f && it.read() == 0x8b }
        if (!gzip) return null
        val result = java.nio.file.Files.createTempFile("tuist-cache-members-", ".gz").toFile()
        try {
            GZIPInputStream(file.inputStream().buffered()).use { input ->
                result.outputStream().buffered().use { output ->
                    forEachChunk(input) { buffer, count ->
                        val member = GZIPOutputStream(object : java.io.FilterOutputStream(output) {
                            override fun close() { flush() }
                            override fun write(bytes: ByteArray, offset: Int, length: Int) { out.write(bytes, offset, length) }
                        })
                        member.use { it.write(buffer, 0, count) }
                        if (result.length() > 100L * 1024 * 1024 || result.length() > file.length() * 1.05) {
                            throw SizeLimitExceeded()
                        }
                    }
                }
            }
            // A compression regression must not turn an accepted entry into an oversized one.
            if (result.length() > 100L * 1024 * 1024 || result.length() > file.length() * 1.05) {
                result.delete()
                return null
            }
            return result
        } catch (_: SizeLimitExceeded) {
            result.delete()
            return null
        } catch (error: Throwable) {
            result.delete()
            throw error
        }
    }

    private fun forEachChunk(input: InputStream, consume: (ByteArray, Int) -> Unit) {
        val buffer = ByteArray(MAX_BYTES)
        var buffered = 0
        var total = 0L
        var ended = false
        while (true) {
            while (!ended && buffered < buffer.size) {
                val read = input.read(buffer, buffered, buffer.size - buffered)
                if (read < 0) ended = true else buffered += read
            }
            if (buffered == 0) break
            val count = cut(buffer, buffered)
            total += count
            if (total > 2L * 1024 * 1024 * 1024) throw SizeLimitExceeded()
            consume(buffer, count)
            buffer.copyInto(buffer, 0, count, buffered)
            buffered -= count
        }
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
}
