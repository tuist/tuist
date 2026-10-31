package dev.tuist.gradle

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.apache.commons.compress.archivers.zip.ZipFile
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermission
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TuistNativePreviewsFunctionalTest {
    @TempDir lateinit var directory: File

    @Test
    fun `Swift public application API registers per-binary tasks but JVM application does not`() {
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest) = MockResponse().setBody("{}")
            }
            server.start()
            fixture(server)
            File(directory, "app/build.gradle").writeText("plugins { id 'swift-application' }")
            val swift = runner(":app:tasks", "--all").build()
            assertTrue(swift.output.contains("tuistShareMainDebug"), swift.output)
            assertTrue(swift.output.contains("tuistShareMainRelease"), swift.output)
            File(directory, "app/build.gradle").writeText("plugins { id 'application' }")
            val jvm = runner(":app:tasks", "--all").build()
            assertTrue(!jvm.output.contains("tuistShare"), jvm.output)
        }
    }

    @Test
    fun `C++ distributions publish explicitly and receipts survive configuration and build cache replay`() {
        val requests = CopyOnWriteArrayList<String>()
        val receipts = ConcurrentHashMap<String, String>()
        val blobs = ConcurrentHashMap<String, ByteArray>()
        var failUploads = false
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val path = request.path.orEmpty()
                    if (!path.contains("/artifacts")) return MockResponse().setBody("{}")
                    requests.add("${request.method} $path")
                    assertEquals("Bearer fixture-token", request.getHeader("Authorization"))
                    val key = path.substringAfter("/publications/").substringBefore("/content/")
                    return when {
                        path.endsWith("/artifacts/") -> MockResponse().setBody(
                            """{"schema":"once.publication_service.v1","destination":"native-fixture"}"""
                        )
                        request.method == "GET" -> receipts[key]?.let { MockResponse().setBody(it) }
                            ?: MockResponse().setResponseCode(404)
                        failUploads -> MockResponse().setResponseCode(503)
                        path.contains("/content/") -> {
                            val bytes = request.body.readByteArray()
                            val digest = "sha256:" + ArtifactPublisher.hexDigest(bytes)
                            assertEquals(path.substringAfter("/content/"), digest)
                            blobs[digest] = bytes
                            MockResponse().setBody("{}")
                        }
                        else -> {
                            val intent = JsonParser.parseString(request.body.readUtf8()).asJsonObject
                            val receipt = JsonObject().apply {
                                addProperty("schema", "once.publication_receipt.v1")
                                addProperty("key", key)
                                addProperty("destination", "native-fixture")
                                add("root", intent["root"])
                            }.toString()
                            receipts[key] = receipt
                            MockResponse().setBody(receipt)
                        }
                    }
                }
            }
            server.start()
            fixture(server)
            runner(":app:assemble", "--build-cache").build()
            assertTrue(requests.isEmpty(), requests.toString())
            val args = arrayOf(":app:tuistShareMainDebug", "--configuration-cache", "--build-cache")
            val first = runner(*args).build()
            assertEquals(TaskOutcome.SUCCESS, first.task(":app:tuistShareMainDebug")?.outcome, first.output)
            assertEquals(1, receipts.size)
            val documents = blobs.values.mapNotNull { runCatching {
                JsonParser.parseString(it.toString(Charsets.UTF_8)).asJsonObject
            }.getOrNull() }
            val metadata = documents.single { it["schema"]?.asString == "tuist.executable.v1" }
            val macos = System.getProperty("os.name").lowercase().contains("mac")
            val architecture = when (System.getProperty("os.arch")) {
                "aarch64", "arm64" -> "arm64"
                "amd64", "x86_64" -> "x86_64"
                else -> error("Native preview fixture requires arm64 or x86_64")
            }
            assertEquals(if (macos) "macos" else "linux", metadata["platform"].asString)
            assertEquals(listOf(architecture), metadata["architectures"].asJsonArray.map { it.asString })
            assertEquals("native-preview", metadata["display_name"].asString)
            val artifact = documents.single { it["schema"]?.asString == "once.artifact.v1" }
            assertTrue(artifact["interfaces"].asJsonObject.has("dev.tuist.executable.v1"))
            val product = artifact["payloads"].asJsonObject["product"].asJsonObject
            assertEquals("application/zip", product["media_type"].asString)
            val archive = File(directory, "preview.zip").apply { writeBytes(blobs.getValue(product["digest"].asString)) }
            val extracted = File(directory, "extracted").apply { mkdirs() }
            ZipFile(archive).use { zip ->
                val entries = zip.entries.asSequence().toList()
                val librarySuffix = if (macos) ".dylib" else ".so"
                assertTrue(entries.any { it.name.endsWith(librarySuffix) }, entries.map { it.name }.toString())
                entries.forEach { entry ->
                    val file = File(extracted, entry.name)
                    if (entry.isDirectory) file.mkdirs() else {
                        file.parentFile.mkdirs()
                        zip.getInputStream(entry).use { input -> file.outputStream().use { input.copyTo(it) } }
                        val permissions = PosixFilePermission.entries.filter { permission ->
                            entry.unixMode and (1 shl (8 - permission.ordinal)) != 0
                        }.toSet()
                        Files.setPosixFilePermissions(file.toPath(), permissions)
                    }
                }
            }
            val manifest = JsonParser.parseString(File(extracted, "tuist-preview.json").readText()).asJsonObject
            assertEquals(metadata["executable"], manifest["executable"])
            val launcher = File(extracted, manifest["executable"].asString)
            assertTrue(launcher.canExecute())
            assertTrue(File(extracted, "lib/native-preview").canExecute())
            val process = ProcessBuilder(launcher.absolutePath).directory(extracted).redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().readText()
            assertEquals(0, process.waitFor(), output)
            assertEquals("runtime library works\n", output)

            requests.clear()
            val second = runner(*args).build()
            assertTrue(second.output.contains("Configuration cache entry reused"), second.output)
            assertTrue(second.output.contains("Already published"), second.output)
            assertEquals(2, requests.size)
            assertTrue(requests.all { it.startsWith("GET ") })
            runner("clean").build()
            requests.clear()
            val restored = runner(*args).build()
            assertTrue(restored.tasks.any { it.outcome == TaskOutcome.FROM_CACHE }, restored.output)
            assertTrue(restored.output.contains("Already published"), restored.output)
            assertEquals(2, requests.size)
            assertTrue(requests.all { it.startsWith("GET ") }, requests.toString())

            requests.clear()
            failUploads = true
            val failure = runner(":app:tuistShareMainRelease").buildAndFail()
            assertTrue(failure.output.contains("publication is not confirmed"), failure.output)
            assertEquals(1, requests.count { it.startsWith("POST ") })

            requests.clear()
            // Leave the generated launcher intact: validation must inspect its actual ELF target.
            File(directory, "app/build/install/main/debug/lib/native-preview").writeText("unsupported binary")
            val unsupported = runner(":app:tuistShareMainDebug", "-x", ":app:installDebug").buildAndFail()
            assertTrue(unsupported.output.contains("Expected a 64-bit"), unsupported.output)
            assertTrue(requests.isEmpty(), requests.toString())
        }
    }

    private fun fixture(server: MockWebServer) {
        File(directory, "settings.gradle").writeText("""
            plugins { id 'dev.tuist' }
            tuist {
                project = 'test-account/test-project'
                url = '${server.url("/")}'
                network { proxy = false }
                buildCache { enabled = false }
                uploadInBackground = false
                testQuarantine { enabled = false }
            }
            rootProject.name = 'native-preview'
            include ':app', ':greeting'
        """.trimIndent())
        File(directory, "gradle.properties").writeText("org.gradle.jvmargs=-Xmx384m -XX:ActiveProcessorCount=2\norg.gradle.workers.max=1\n")
        File(directory, "build.gradle").writeText("")
        File(directory, "app/build.gradle").apply { parentFile.mkdirs() }.writeText("""
            plugins { id 'cpp-application' }
            application { baseName = 'native-preview' }
            dependencies { implementation project(':greeting') }
        """.trimIndent())
        File(directory, "greeting/build.gradle").apply { parentFile.mkdirs() }.writeText("plugins { id 'cpp-library' }")
        File(directory, "greeting/src/main/public/greeting.h").apply { parentFile.mkdirs() }.writeText("void greet();\n")
        File(directory, "greeting/src/main/cpp/greeting.cpp").apply { parentFile.mkdirs() }.writeText(
            "#include <iostream>\nvoid greet() { std::cout << \"runtime library works\\n\"; }\n"
        )
        File(directory, "app/src/main/cpp/main.cpp").apply { parentFile.mkdirs() }.writeText(
            "#include <greeting.h>\nint main() { greet(); }\n"
        )
    }

    private fun runner(vararg args: String) = GradleRunner.create()
        .withProjectDir(directory).withPluginClasspath().withGradleVersion("8.12.1")
        .withEnvironment(System.getenv().filterKeys { !it.startsWith("TUIST_") } + ("TUIST_TOKEN" to "fixture-token"))
        .withArguments(*args, "--stacktrace", "--max-workers=1", "--no-watch-fs")
}
