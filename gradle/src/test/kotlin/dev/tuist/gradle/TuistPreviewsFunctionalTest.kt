package dev.tuist.gradle

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.api.Assumptions.assumeTrue
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TuistPreviewsFunctionalTest {
    @TempDir lateinit var directory: File

    @Test
    fun `native Android build publishes only on request and reuses receipts across caches`() {
        val track = "nightly-\u2028verified"
        val requests = CopyOnWriteArrayList<String>()
        val receipts = ConcurrentHashMap<String, String>()
        val blobs = ConcurrentHashMap<String, ByteArray>()
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
                            """{"schema":"once.publication_service.v1","destination":"test-destination"}"""
                        )
                        request.method == "GET" -> receipts[key]?.let { MockResponse().setBody(it) }
                            ?: MockResponse().setResponseCode(404)
                        path.contains("/content/") -> {
                            val bytes = request.body.readByteArray()
                            val digest = "sha256:" + MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                            assertEquals(path.substringAfter("/content/"), digest)
                            blobs[digest] = bytes
                            MockResponse().setBody("{}")
                        }
                        else -> {
                            val intent = JsonParser.parseString(request.body.readUtf8()).asJsonObject
                            // Independent canonical wire identity: U+2028 is literal UTF-8, not a JS escape.
                            val root = intent["root"].asJsonObject
                            val canonical = """{"revision":null,"root":{"digest":${root["digest"]},"media_type":"application/vnd.once.artifact-set.v1+json","size_bytes":${root["size_bytes"]}},"schema":"once.publication_intent.v1","target":"gradle::app:debug","track":"$track"}"""
                            val digest = MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray(Charsets.UTF_8))
                                .joinToString("") { "%02x".format(it) }
                            assertEquals("sha256:$digest", key)
                            val receipt = JsonObject().apply {
                                addProperty("schema", "once.publication_receipt.v1")
                                addProperty("key", key)
                                addProperty("destination", "test-destination")
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
            runner(":app:assembleDebug").build()
            assertTrue(requests.isEmpty(), requests.toString())
            val first = runner(":app:tuistShareDebug", "--track", track, "--configuration-cache", "--build-cache").build()
            assertEquals(TaskOutcome.SUCCESS, first.task(":app:tuistShareDebug")?.outcome, first.output)
            assertTrue(first.output.contains("Published sha256:"), first.output)
            assertEquals(1, receipts.size)
            val metadata = blobs.values.mapNotNull { bytes -> runCatching { JsonParser.parseString(bytes.toString(Charsets.UTF_8)).asJsonObject }.getOrNull() }
                .single { it["schema"]?.asString == "once.android_application.v1" }
            assertEquals("dev.tuist.preview.fixture", metadata["application_id"].asString)
            assertEquals("1.2' quoted", metadata["version_name"].asString)
            assertEquals("42", metadata["version_code"].asString)
            assertTrue(metadata["signature_verified"].asBoolean)
            assertTrue(blobs.values.any { it.contentEquals(File(directory, "app/build/outputs/apk/debug/app-debug.apk").readBytes()) })
            requests.clear()
            val second = runner(":app:tuistShareDebug", "--track", track, "--configuration-cache", "--build-cache").build()
            assertTrue(second.output.contains("Configuration cache entry reused"), second.output)
            assertTrue(second.output.contains("Already published"), second.output)
            assertEquals(2, requests.size)
            assertTrue(requests.all { it.startsWith("GET ") })
            runner(":app:clean").build()
            requests.clear()
            val restored = runner(":app:tuistShareDebug", "--track", track, "--configuration-cache", "--build-cache").build()
            assertTrue(restored.tasks.any { it.outcome == TaskOutcome.FROM_CACHE }, restored.output)
            assertTrue(restored.output.contains("Already published"), restored.output)
            assertTrue(requests.all { it.startsWith("GET ") }, requests.toString())
            requests.clear()
            val unsigned = runner(":app:tuistShareRelease").buildAndFail()
            assertTrue(unsigned.output.contains("unsigned or its signature is invalid"), unsigned.output)
            assertTrue(requests.isEmpty(), requests.toString())
            runner(":app:assembleDebug").build()
            assertTrue(requests.isEmpty(), requests.toString())
            val manifest = File(directory, "app/src/main/AndroidManifest.xml")
            val original = manifest.readText()
            manifest.writeText(original.replace("</manifest>", "<instrumentation android:name=\"android.test.InstrumentationTestRunner\" android:targetPackage=\"dev.tuist.preview.fixture\"/></manifest>"))
            val instrumentation = runner(":app:tuistShareDebug").buildAndFail()
            assertTrue(instrumentation.output.contains("Instrumentation APKs are not application previews"), instrumentation.output)
            assertTrue(requests.isEmpty(), requests.toString())
            manifest.writeText("not an Android manifest")
            val failedBuild = runner(":app:tuistShareDebug").buildAndFail()
            assertTrue(failedBuild.task(":app:tuistShareDebug") == null, failedBuild.output)
            assertTrue(requests.isEmpty(), requests.toString())
            manifest.writeText(original)
            File(directory, "app/build.gradle").appendText("\n" + """
                android { splits { abi { enable true; reset(); include 'x86_64', 'arm64-v8a'; universalApk false } } }
            """.trimIndent())
            val split = runner(":app:tuistShareDebug").buildAndFail()
            assertTrue(split.output.contains("single universal APK"), split.output)
            assertTrue(requests.isEmpty(), requests.toString())
        }
    }

    @Test
    fun `publication failures fail the requested task without retrying POST`() {
        val writes = CopyOnWriteArrayList<String>()
        val lookup = AtomicReference<String?>(null)
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val path = request.path.orEmpty()
                    if (!path.contains("/artifacts")) return MockResponse().setBody("{}")
                    if (request.method == "POST") {
                        writes.add(path)
                        return MockResponse().setResponseCode(503)
                    }
                    return if (path.endsWith("/artifacts/")) MockResponse().setBody(
                        """{"schema":"once.publication_service.v1","destination":"test-destination"}"""
                    ) else lookup.get()?.let { MockResponse().setBody(it) } ?: MockResponse().setResponseCode(404)
                }
            }
            server.start()
            fixture(server)
            val result = runner(":app:tuistShareDebug").buildAndFail()
            assertTrue(result.output.contains("publication is not confirmed"), result.output)
            assertEquals(1, writes.size)
            for (invalidReceipt in listOf("", "null", "{}")) {
                writes.clear()
                lookup.set(invalidReceipt)
                val invalid = runner(":app:tuistShareDebug").buildAndFail()
                assertTrue(invalid.output.contains("publication"), invalid.output)
                assertTrue(writes.isEmpty(), writes.toString())
            }
        }
    }

    private fun fixture(server: MockWebServer) {
        val sdk = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
        assumeTrue(sdk != null && File(sdk, "platforms/android-35").isDirectory, "Requires Android SDK 35")
        File(directory, "local.properties").writeText("sdk.dir=$sdk\n")
        File(directory, "settings.gradle").writeText("""
            pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
            plugins { id 'dev.tuist' }
            dependencyResolutionManagement { repositories { google(); mavenCentral() } }
            tuist {
                project = 'test-account/test-project'
                url = '${server.url("/")}'
                network { proxy = false }
                buildCache { enabled = false }
                uploadInBackground = false
                testQuarantine { enabled = false }
            }
            rootProject.name = 'preview-fixture'
            include ':app'
        """.trimIndent())
        File(directory, "build.gradle").writeText("plugins { id 'com.android.application' version '8.8.2' apply false }")
        val app = File(directory, "app").apply { mkdirs() }
        File(app, "build.gradle").writeText("""
            plugins { id 'com.android.application' }
            android {
                namespace 'dev.tuist.preview.fixture'
                compileSdk 35
                defaultConfig {
                    applicationId 'dev.tuist.preview.fixture'
                    minSdk 23
                    targetSdk 35
                    versionCode 42
                    versionName "1.2' quoted"
                }
            }
        """.trimIndent())
        File(app, "src/main/AndroidManifest.xml").apply { parentFile.mkdirs() }.writeText(
            """<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="Preview fixture"/></manifest>"""
        )
    }

    private fun runner(vararg args: String) = GradleRunner.create()
        .withProjectDir(directory).withPluginClasspath().withGradleVersion("8.12.1")
        .withEnvironment(System.getenv().filterKeys { !it.startsWith("TUIST_") } + ("TUIST_TOKEN" to "fixture-token"))
        .withArguments(*args, "--stacktrace", "--max-workers=2", "--no-watch-fs")
}
