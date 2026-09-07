package dev.tuist.gradle

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.Properties
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ChunkedGradleBuildTest {
    @TempDir lateinit var directory: File

    @Test
    @EnabledIfEnvironmentVariable(named = "TUIST_CHUNKING_TEST_URL", matches = "http://127\\.0\\.0\\.1:[0-9]+")
    fun `real Gradle builds restore chunked uploads with both Tuist and the built in reader`() {
        val base = System.getenv("TUIST_CHUNKING_TEST_URL")
        val project = "gradle-build-${System.nanoTime()}"
        val completed = AtomicInteger()
        val forwarding = HttpClient.newHttpClient()
        MockWebServer().use { proxy ->
            proxy.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    var path = request.path!!
                    if (path.startsWith("/legacy/")) {
                        path = "/api/cache/gradle/${path.removePrefix("/legacy/")}?account_handle=chunking-test&project_handle=$project"
                    }
                    val body = request.body.readByteArray()
                    val builder = HttpRequest.newBuilder(URI.create(base + path))
                        .method(request.method!!, HttpRequest.BodyPublishers.ofByteArray(body))
                    request.getHeader("Content-Type")?.let { builder.header("Content-Type", it) }
                    val response = forwarding.send(builder.build(), HttpResponse.BodyHandlers.ofByteArray())
                    if (path.startsWith("/api/cache/chunks/complete") && response.statusCode() == 204) completed.incrementAndGet()
                    return MockResponse().setResponseCode(response.statusCode()).setBody(okio.Buffer().write(response.body()))
                }
            }
            val metadata = Properties().apply {
                ChunkedGradleBuildTest::class.java.classLoader.getResourceAsStream("plugin-under-test-metadata.properties")!!.use(::load)
            }
            val classpath = metadata.getProperty("implementation-classpath").split(File.pathSeparator)
                .joinToString(",") { "'${it.replace("\\", "\\\\").replace("'", "\\'")}'" }
            File(directory, "settings.gradle").writeText("""
                buildscript { dependencies { classpath files($classpath) } }
                import dev.tuist.gradle.*
                import org.gradle.caching.*
                import org.gradle.caching.configuration.AbstractBuildCache
                class FixtureCache extends AbstractBuildCache {}
                class FixtureFactory implements BuildCacheServiceFactory<FixtureCache> {
                    BuildCacheService createBuildCacheService(FixtureCache config, BuildCacheServiceFactory.Describer describer) {
                        describer.type('Tuist chunking test')
                        def provider = { boolean refresh -> new CacheConfiguration('${proxy.url("/")}', 'test', 'chunking-test', '$project') } as ConfigurationProvider
                        return new TuistBuildCacheService(new TuistHttpClient(provider, new TuistHttpClients(), 30000, 60000), true)
                    }
                }
                rootProject.name = 'chunking-build'
                buildCache {
                    registerBuildCacheService(FixtureCache, FixtureFactory)
                    local { enabled = false }
                    remote(FixtureCache) { push = true }
                }
            """.trimIndent())
            File(directory, "build.gradle").writeText("""
                import java.nio.file.Files
                @CacheableTask
                abstract class Fixture extends DefaultTask {
                    @InputFile @PathSensitive(PathSensitivity.NONE) abstract RegularFileProperty getSource()
                    @OutputFile abstract RegularFileProperty getDestination()
                    @TaskAction void produce() {
                        def output = destination.get().asFile
                        output.parentFile.mkdirs()
                        Files.copy(source.get().asFile.toPath(), output.toPath())
                    }
                }
                tasks.register('fixture', Fixture) {
                    source = layout.projectDirectory.file('input.bin')
                    destination = layout.buildDirectory.file('output.bin')
                }
            """.trimIndent())
            val bytes = chunkingCorpus()
            File(directory, "input.bin").writeBytes(bytes)
            fun run() = GradleRunner.create().withProjectDir(directory)
                .withArguments("fixture", "--build-cache", "--configuration-cache", "--no-watch-fs", "--stacktrace").build()
            assertEquals(TaskOutcome.SUCCESS, run().task(":fixture")?.outcome)
            assertEquals(1, completed.get(), "the real Gradle writer must use negotiated completion")
            val output = File(directory, "build/output.bin")
            assertContentEquals(bytes, output.readBytes())
            assertTrue(output.delete())
            val warm = run()
            assertEquals(TaskOutcome.FROM_CACHE, warm.task(":fixture")?.outcome)
            assertTrue(warm.output.contains("Reusing configuration cache"))
            assertContentEquals(bytes, output.readBytes())
            File(directory, "settings.gradle").writeText("""
                buildscript { dependencies { classpath files($classpath) } }
                rootProject.name = 'chunking-build'
                buildCache {
                    local { enabled = false }
                    remote(HttpBuildCache) {
                        url = '${proxy.url("/legacy/")}'
                        allowInsecureProtocol = true
                        push = false
                    }
                }
            """.trimIndent())
            assertTrue(output.delete())
            val legacy = run()
            assertEquals(TaskOutcome.FROM_CACHE, legacy.task(":fixture")?.outcome, legacy.output)
            assertContentEquals(bytes, output.readBytes())
        }
    }
}
