package dev.tuist.gradle

import com.google.gson.Gson
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.TaskAction
import org.gradle.api.tasks.options.Option
import org.gradle.work.DisableCachingByDefault
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.time.LocalDateTime

@DisableCachingByDefault(because = "Explicit publication is a side effect, deduplicated by server receipts")
abstract class TuistShareExecutable : DefaultTask() {
    @get:InputDirectory abstract val distribution: DirectoryProperty
    @get:InputFile abstract val nativeExecutable: RegularFileProperty
    @get:InputFile abstract val launcher: RegularFileProperty
    @get:Internal abstract val projectDirectory: DirectoryProperty
    @get:Input abstract val serverUrl: Property<String>
    @get:Input @get:Optional abstract val tuistProject: Property<String>
    @get:Input abstract val useEnvironmentProxy: Property<Boolean>
    @get:Input abstract val publicationTarget: Property<String>
    @get:Input @get:Optional abstract val track: Property<String>

    @Option(option = "track", description = "Publish to this preview track")
    fun track(value: String) { track.set(value) }

    @TaskAction
    fun share() {
        // Detect the *binary*, not InstallExecutable's architecture-independent shell wrapper.
        val target = ExecutablePreviewTarget.read(nativeExecutable.get().asFile)
        val root = distribution.get().asFile.toPath()
        // Gradle installs the binary and runtime libraries in lib/, and its launcher sets
        // LD_LIBRARY_PATH/DYLD_LIBRARY_PATH. Running lib/<binary> directly loses those dependencies.
        val entrypoint = root.relativize(launcher.get().asFile.toPath()).toString().replace(File.separatorChar, '/')
        require(!entrypoint.startsWith("../") && !File(entrypoint).isAbsolute)
        val archive = File(temporaryDir, "application.zip")
        try {
            ExecutablePreviewArchive.write(distribution.get().asFile, entrypoint, archive)
            val metadata = mapOf(
                "schema" to "tuist.executable.v1", "display_name" to File(entrypoint).name,
                "platform" to target.platform, "architectures" to target.architectures,
                "executable" to entrypoint
            )
            val clients = TuistHttpClients(useEnvironmentProxy = useEnvironmentProxy.get())
            val publisher = ArtifactPublisher(
                ServerConfigurationProvider(tuistProject.orNull, serverUrl.get(), projectDirectory.get().asFile, clients), clients
            )
            val status = publisher.publish(archive, metadata, publicationTarget.get(), track.orNull,
                "application/zip", "dev.tuist.executable.v1")
            logger.lifecycle("Tuist: $status. Preview processing is asynchronous; open your project's Previews page.")
        } finally {
            archive.delete()
        }
    }
}

/** Mirrors ExecutablePreviewTarget in the CLI, without executing untrusted publisher code. */
internal data class ExecutablePreviewTarget(val platform: String, val architectures: List<String>) {
    companion object {
        fun read(file: File): ExecutablePreviewTarget {
            val bytes = file.inputStream().use { it.readNBytes(4096) }
            fun word(offset: Int, little: Boolean = true): Long? {
                if (offset < 0 || offset + 4 > bytes.size) return null
                val indices = if (little) (offset + 3 downTo offset) else (offset..offset + 3)
                return indices.fold(0L) { value, index -> (value shl 8) or (bytes[index].toLong() and 255) }
            }
            fun arch(cpu: Long?) = when (cpu) {
                0x0100000cL -> "arm64"
                0x01000007L -> "x86_64"
                else -> null
            }
            if (bytes.take(2) == listOf(0x23.toByte(), 0x21.toByte())) {
                val os = System.getProperty("os.name").lowercase()
                require(os.contains("linux") || os.contains("mac")) { "Unsupported script platform" }
                return ExecutablePreviewTarget(if (os.contains("mac")) "macos" else "linux", emptyList())
            }
            if (word(0) == 0x464c457fL && bytes.size >= 64 && bytes[4] == 2.toByte() && bytes[5] == 1.toByte()) {
                val machine = (bytes[18].toInt() and 255) or ((bytes[19].toInt() and 255) shl 8)
                val architecture = mapOf(62 to "x86_64", 183 to "arm64")[machine]
                if (architecture != null) return ExecutablePreviewTarget("linux", listOf(architecture))
            }
            if (word(0) == 0xfeedfacfL && word(12) == 2L) {
                arch(word(4))?.let { return ExecutablePreviewTarget("macos", listOf(it)) }
            }
            val count = word(4, false)?.toInt() ?: 0
            if (word(0, false) == 0xcafebabeL && count in 1..16 && 8 + count * 20 <= bytes.size) {
                val architectures = (0 until count).mapNotNull { arch(word(8 + it * 20, false)) }.distinct().sorted()
                if (architectures.isNotEmpty()) return ExecutablePreviewTarget("macos", architectures)
            }
            error("Expected a 64-bit macOS Mach-O, Linux ELF executable, or a script with a shebang.")
        }
    }
}

/** Stable ordering, timestamps and Unix modes make publication identities independent of install time. */
internal object ExecutablePreviewArchive {
    fun write(directory: File, executable: String, archive: File) {
        val root = directory.toPath()
        require(Files.isExecutable(root.resolve(executable))) { "Preview entry point is not executable" }
        require(!Files.exists(root.resolve("tuist-preview.json"), NOFOLLOW_LINKS)) { "Distribution already contains tuist-preview.json" }
        ZipArchiveOutputStream(archive).use { zip ->
            fun entry(name: String, mode: Int, write: () -> Unit) {
                zip.putArchiveEntry(ZipArchiveEntry(name).apply {
                    setTimeLocal(LocalDateTime.of(1980, 1, 1, 0, 0))
                    unixMode = mode
                })
                write()
                zip.closeArchiveEntry()
            }
            Files.walk(root).use { paths ->
                paths.filter { it != root }.sorted().forEach { path ->
                    val name = root.relativize(path).toString().replace(File.separatorChar, '/')
                    require('\\' !in name) { "Unsupported distribution path" }
                    when {
                        Files.isSymbolicLink(path) -> {
                            val target = Files.readSymbolicLink(path)
                            require(!target.isAbsolute && path.parent.resolve(target).normalize().startsWith(root)) {
                                "Distribution symlink escapes its root: $name"
                            }
                            entry(name, 0xa1ff) { zip.write(target.toString().toByteArray(Charsets.UTF_8)) }
                        }
                        Files.isDirectory(path, NOFOLLOW_LINKS) -> entry("$name/", 0x41ed) {}
                        else -> {
                            require(Files.isRegularFile(path, NOFOLLOW_LINKS)) { "Unsupported distribution file: $name" }
                            val permissions = Files.getPosixFilePermissions(path)
                            val mode = permissions.fold(0x8000) { bits, permission ->
                                bits or (1 shl (8 - permission.ordinal))
                            }
                            entry(name, mode) { Files.newInputStream(path).use { it.copyTo(zip) } }
                        }
                    }
                }
            }
            entry("tuist-preview.json", 0x81a4) {
                zip.write(Gson().toJson(mapOf("executable" to executable)).toByteArray(Charsets.UTF_8))
            }
        }
    }
}
