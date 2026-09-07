package dev.tuist.gradle

import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** At most 512 two-mebibyte slots and one staging file across all projects.
 * Each bucket has four ways. Every read is verified, so eviction or disk corruption is only a miss.
 */
internal class LocalChunkCache(private val directory: File, private val scope: String) {
    internal fun path(digest: ContentDefinedChunking.Digest): File = paths(digest).first()

    private fun paths(digest: ContentDefinedChunking.Digest): List<File> {
        val hash = ContentDefinedChunking.digest("$scope\u0000${digest.hash}\u0000${digest.size}".toByteArray()).hash
        return (0..3).map { File(directory, "%02x-%d".format(hash.take(4).toInt(16) % 128, it)) }
    }

    fun get(digest: ContentDefinedChunking.Digest): ByteArray? = try {
        if (digest.size !in 1..ContentDefinedChunking.MAX_BYTES) null
        else paths(digest).firstNotNullOfOrNull { file ->
            if (file.length() != digest.size) null
            else runCatching { file.inputStream().use { it.readNBytes(digest.size.toInt() + 1) } }.getOrNull()
                ?.takeIf { ContentDefinedChunking.digest(it) == digest }
        }
    } catch (_: Exception) { null }

    fun put(digest: ContentDefinedChunking.Digest, bytes: ByteArray) {
        synchronized(writeLock) {
            if (bytes.size !in 1..ContentDefinedChunking.MAX_BYTES || ContentDefinedChunking.digest(bytes) != digest) return
            try {
                directory.mkdirs()
                RandomAccessFile(File(directory, ".lock"), "rw").use { lockFile ->
                    val lock = lockFile.channel.lock()
                    lock.use {
                        if (get(digest) != null) return
                        val destination = paths(digest).minBy { it.lastModified() }
                        val pending = File(directory, ".pending")
                        try {
                            pending.writeBytes(bytes)
                            Files.move(pending.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                        } finally { pending.delete() }
                    }
                }
            } catch (_: Exception) { /* A busy or unwritable cache never prevents a remote restore. */ }
        }
    }

    companion object { private val writeLock = Any() }
}
