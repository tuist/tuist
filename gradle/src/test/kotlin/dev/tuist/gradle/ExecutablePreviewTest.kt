package dev.tuist.gradle

import org.apache.commons.compress.archivers.zip.ZipFile
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.nio.file.attribute.FileTime
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ExecutablePreviewTest {
    @TempDir lateinit var directory: File

    @Test
    fun `target detection follows CLI ELF Mach-O fat and shebang rules`() {
        val file = File(directory, "entrypoint")
        fun target(bytes: ByteArray): ExecutablePreviewTarget {
            file.writeBytes(bytes)
            return ExecutablePreviewTarget.read(file)
        }
        for ((machine, arch) in listOf(62 to "x86_64", 183 to "arm64")) {
            val elf = ByteArray(64)
            ByteBuffer.wrap(elf).order(ByteOrder.LITTLE_ENDIAN).apply {
                putInt(0, 0x464c457f); put(4, 2); put(5, 1); putShort(18, machine.toShort())
            }
            assertEquals(ExecutablePreviewTarget("linux", listOf(arch)), target(elf))
            elf[5] = 2
            assertFailsWith<IllegalStateException> { target(elf) }
        }
        for ((cpu, arch) in listOf(0x01000007 to "x86_64", 0x0100000c to "arm64")) {
            val macho = ByteBuffer.allocate(64).order(ByteOrder.LITTLE_ENDIAN).apply {
                putInt(0, 0xfeedfacf.toInt()); putInt(4, cpu); putInt(12, 2)
            }.array()
            assertEquals(ExecutablePreviewTarget("macos", listOf(arch)), target(macho))
            macho[12] = 6 // dylib, not an executable
            assertFailsWith<IllegalStateException> { target(macho) }
        }
        val fat = ByteBuffer.allocate(48).order(ByteOrder.BIG_ENDIAN).apply {
            putInt(0, 0xcafebabe.toInt()); putInt(4, 2)
            putInt(8, 0x01000007); putInt(28, 0x0100000c)
        }.array()
        assertEquals(ExecutablePreviewTarget("macos", listOf("arm64", "x86_64")), target(fat))
        assertFailsWith<IllegalStateException> { target(fat.copyOf(20)) }
        assertTrue(target("#!/bin/sh\nexit 0\n".toByteArray()).architectures.isEmpty())
        listOf(byteArrayOf(), "MZwindows".toByteArray(), "not executable".toByteArray()).forEach {
            assertFailsWith<IllegalStateException> { target(it) }
        }
    }

    @Test
    fun `distribution zip preserves resources modes and symlinks with stable identity`() {
        val root = File(directory, "distribution").apply { mkdirs() }
        val launcher = File(root, "run").apply { writeText("#!/bin/sh\n"); setExecutable(true, false) }
        File(root, "lib").mkdir()
        File(root, "lib/data.txt").writeText("resource")
        Files.createSymbolicLink(File(root, "lib/alias").toPath(), File("data.txt").toPath())
        val first = File(directory, "first.zip")
        ExecutablePreviewArchive.write(root, "run", first)
        Files.setLastModifiedTime(launcher.toPath(), FileTime.fromMillis(1000000))
        val second = File(directory, "second.zip")
        ExecutablePreviewArchive.write(root, "run", second)
        assertContentEquals(first.readBytes(), second.readBytes())
        ZipFile(first).use { zip ->
            assertTrue(zip.getEntry("run").unixMode and 0x49 != 0)
            assertTrue(zip.getEntry("lib/alias").isUnixSymlink)
            assertEquals("resource", zip.getInputStream(zip.getEntry("lib/data.txt")).bufferedReader().readText())
            assertEquals("{\"executable\":\"run\"}", zip.getInputStream(zip.getEntry("tuist-preview.json")).bufferedReader().readText())
        }
        Files.createSymbolicLink(File(root, "escape").toPath(), File("../../outside").toPath())
        assertFailsWith<IllegalArgumentException> { ExecutablePreviewArchive.write(root, "run", second) }
    }
}
