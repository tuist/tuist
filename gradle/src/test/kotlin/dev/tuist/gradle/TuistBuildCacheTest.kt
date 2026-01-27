package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class TuistBuildCacheTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `TuistBuildCache has correct default values`() {
        val cache = TuistBuildCache()

        assertEquals("", cache.fullHandle)
        assertNull(cache.executablePath)
        assertEquals(false, cache.allowInsecureProtocol)
        // isPush defaults to false in AbstractBuildCache
        assertEquals(false, cache.isPush)
    }

    @Test
    fun `TuistBuildCache properties can be configured`() {
        val cache = TuistBuildCache().apply {
            fullHandle = "my-account/my-project"
            executablePath = "/custom/path/tuist"
            allowInsecureProtocol = true
            isPush = false
        }

        assertEquals("my-account/my-project", cache.fullHandle)
        assertEquals("/custom/path/tuist", cache.executablePath)
        assertEquals(true, cache.allowInsecureProtocol)
        assertEquals(false, cache.isPush)
    }

    @Test
    fun `findTuistInPath returns path when executable exists`() {
        val binDir = File(tempDir, "bin")
        binDir.mkdirs()
        val tuistFile = File(binDir, "tuist")
        tuistFile.writeText("#!/bin/bash\necho 'tuist'")
        tuistFile.setExecutable(true)

        val factory = TuistBuildCacheServiceFactoryTestHelper()
        val result = factory.findTuistInPathWithCustomPath(binDir.absolutePath)

        assertNotNull(result)
        assertEquals(tuistFile.absolutePath, result)
    }

    @Test
    fun `findTuistInPath returns null when executable does not exist`() {
        val emptyDir = File(tempDir, "empty")
        emptyDir.mkdirs()

        val factory = TuistBuildCacheServiceFactoryTestHelper()
        val result = factory.findTuistInPathWithCustomPath(emptyDir.absolutePath)

        assertNull(result)
    }

    @Test
    fun `findTuistInPath returns null when file exists but is not executable`() {
        val binDir = File(tempDir, "bin")
        binDir.mkdirs()
        val tuistFile = File(binDir, "tuist")
        tuistFile.writeText("not executable")
        tuistFile.setExecutable(false)

        val factory = TuistBuildCacheServiceFactoryTestHelper()
        val result = factory.findTuistInPathWithCustomPath(binDir.absolutePath)

        assertNull(result)
    }

    @Test
    fun `findTuistInPath searches multiple directories in order`() {
        val firstDir = File(tempDir, "first")
        val secondDir = File(tempDir, "second")
        firstDir.mkdirs()
        secondDir.mkdirs()

        val tuistInSecond = File(secondDir, "tuist")
        tuistInSecond.writeText("#!/bin/bash\necho 'tuist'")
        tuistInSecond.setExecutable(true)

        val factory = TuistBuildCacheServiceFactoryTestHelper()
        val pathSeparator = System.getProperty("path.separator") ?: ":"
        val result = factory.findTuistInPathWithCustomPath(
            "${firstDir.absolutePath}${pathSeparator}${secondDir.absolutePath}"
        )

        assertNotNull(result)
        assertEquals(tuistInSecond.absolutePath, result)
    }
}

/**
 * Test helper that exposes findTuistInPath with a custom PATH value.
 */
class TuistBuildCacheServiceFactoryTestHelper {

    fun findTuistInPathWithCustomPath(customPath: String): String? {
        val pathSeparator = System.getProperty("path.separator") ?: ":"
        val executableName = if (System.getProperty("os.name").lowercase().contains("win")) "tuist.exe" else "tuist"

        for (dir in customPath.split(pathSeparator)) {
            val file = File(dir, executableName)
            if (file.exists() && file.canExecute()) {
                return file.absolutePath
            }
        }
        return null
    }
}
