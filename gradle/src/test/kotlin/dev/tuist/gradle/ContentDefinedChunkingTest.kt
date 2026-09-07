package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal fun chunkingCorpus(): ByteArray {
    var state = 0x12345678L
    return ByteArray(8 * 1024 * 1024) {
        state = state xor (state shl 13)
        state = state xor (state ushr 7)
        state = state xor (state shl 17)
        state.toByte()
    }
}

class ContentDefinedChunkingTest {
    @TempDir lateinit var directory: File

    @Test fun `boundaries match the Rust reference including odd final lengths`() {
        val bytes = chunkingCorpus()
        val artifact = ContentDefinedChunking.scan(bytes.inputStream())
        assertEquals(listOf(529076, 595136, 418015, 222683, 617331, 182609, 709558, 568609, 683124,
            161158, 704587, 540566, 686652, 721374, 550320, 333401, 164409), artifact.chunks.map { it.digest.size.toInt() })
        assertEquals(ContentDefinedChunking.digest(bytes), artifact.digest)
        val changed = bytes.copyOfRange(0, 1_000_000) + "an insertion".toByteArray() + bytes.copyOfRange(1_000_000, bytes.size)
        val known = artifact.chunks.map { it.digest }.toSet()
        val reused = ContentDefinedChunking.scan(changed.inputStream()).chunks.filter { it.digest in known }.sumOf { it.digest.size }
        assertTrue(reused > bytes.size * 3 / 4)
        assertEquals(listOf(2L * 1024 * 1024, 1L), ContentDefinedChunking.scan(ByteArray(2 * 1024 * 1024 + 1).inputStream()).chunks.map { it.digest.size })
    }

    @Test fun `independent gzip members preserve bytes and localize compression changes`() {
        val bytes = chunkingCorpus()
        val changed = bytes.copyOfRange(0, 1_000_000) + "an insertion".toByteArray() + bytes.copyOfRange(1_000_000, bytes.size)
        val prepared = listOf(bytes, changed).mapIndexed { index, data ->
            val source = File(directory, "$index.gz")
            GZIPOutputStream(source.outputStream()).use { it.write(data) }
            val output = requireNotNull(ContentDefinedChunking.recompressGzip(source))
            assertContentEquals(data, GZIPInputStream(output.inputStream()).use { it.readBytes() })
            output
        }
        try {
            val known = ContentDefinedChunking.scan(prepared[0]).chunks.map { it.digest }.toSet()
            val reused = ContentDefinedChunking.scan(prepared[1]).chunks.filter { it.digest in known }.sumOf { it.digest.size }
            assertTrue(reused > prepared[1].length() * 3 / 4, "reused=$reused")
        } finally { prepared.forEach { it.delete() } }
    }
}
