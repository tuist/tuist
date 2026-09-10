package dev.tuist.gradle

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.math.roundToLong
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class BuildExecutionTelemetryIntegrationTest {
    @TempDir lateinit var directory: File

    @ParameterizedTest
    @ValueSource(strings = ["8.14.3", "9.2.1"])
    fun `reports actual remote operations on configuration cache reuse`(version: String) {
        val reports = LinkedBlockingQueue<JsonObject>()
        val artifacts = ConcurrentHashMap<String, ByteArray>()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val path = request.path.orEmpty()
                    if (path.endsWith("/gradle/builds")) {
                        val report = JsonParser.parseString(request.body.readUtf8()).asJsonObject
                        reports.add(report)
                        return MockResponse().setResponseCode(201).setBody("{\"id\":\"${report["id"].asString}\"}")
                    }
                    if (path.startsWith("/cache/")) {
                        if (request.method == "PUT") {
                            artifacts[path] = request.body.readByteArray()
                            return MockResponse().setResponseCode(200)
                        }
                        return artifacts[path]?.let { MockResponse().setBody(Buffer().write(it)) }
                            ?: MockResponse().setResponseCode(404)
                    }
                    return MockResponse().setResponseCode(200).setBody("{\"endpoints\":[\"${server.url("/")}\"]}")
                }
            }
            server.start()
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist {
                    project = 'test/telemetry'
                    url = '${server.url("/")}'
                    uploadInBackground = false
                    buildCache { enabled = false }
                }
                rootProject.name = 'telemetry'
                include 'core', 'feature', 'app'
                buildCache {
                    local { enabled = false }
                    remote(HttpBuildCache) {
                        url = '${server.url("/cache/")}'
                        allowInsecureProtocol = true
                        push = true
                    }
                }
            """.trimIndent())
            File(directory, "build.gradle").writeText("""
                subprojects { apply plugin: 'java-library' }
                project(':core') { tasks.named('compileJava') { outputs.doNotCacheIf('Disabled for this task') { true } } }
                project(':app') {
                    dependencies {
                        implementation project(':core')
                        implementation project(':feature')
                    }
                }
            """.trimIndent())
            listOf("core", "feature", "app").forEach { module ->
                File(directory, "$module/src/main/java/example/${module.replaceFirstChar { it.uppercase() }}.java").apply {
                    parentFile.mkdirs()
                    writeText("package example; public class ${module.replaceFirstChar { it.uppercase() }} {}")
                }
            }

            fun run(vararg extra: String): Pair<String, JsonObject> {
                val result = GradleRunner.create().withProjectDir(directory).withPluginClasspath().withGradleVersion(version)
                    .withEnvironment(System.getenv().filterKeys { it !in setOf("TUIST_URL", "TUIST_CACHE_ENDPOINT") } + ("TUIST_TOKEN" to "test-only-token"))
                    .withArguments(listOf("clean", ":app:jar", "--configuration-cache", "--build-cache", "--parallel", "--no-watch-fs", "--stacktrace") + extra)
                    .build()
                val report = assertNotNull(reports.poll(20, TimeUnit.SECONDS), result.output)
                return result.output to report
            }

            val (_, cold) = run()
            val compile = cold.getAsJsonArray("tasks").map { it.asJsonObject }
                .first { it["task_path"].asString == ":app:compileJava" }
            assertEquals("executed", compile["outcome"].asString)
            assertEquals("miss", compile.getAsJsonObject("execution")["remote_cache_lookup_outcome"].asString)
            assertTrue(compile["remote_cache_stored"].asBoolean)
            assertTrue(compile.getAsJsonObject("execution")["remote_cache_upload_duration_ms"].asLong >= 0)
            assertTrue(!compile.getAsJsonObject("execution").has("remote_cache_download_duration_ms"))
            val disabled = cold.getAsJsonArray("tasks").map { it.asJsonObject }
                .first { it["task_path"].asString == ":core:compileJava" }
            assertEquals("disabled", disabled.getAsJsonObject("execution")["cacheability"].asString)
            assertTrue(!disabled["cacheable"].asBoolean)


            val (output, warm) = run()
            assertTrue(output.contains("Reusing configuration cache"), output)
            val cached = warm.getAsJsonArray("tasks").map { it.asJsonObject }
                .first { it["task_path"].asString == ":app:compileJava" }
            assertEquals("remote_hit", cached["outcome"].asString)
            assertTrue(cached.getAsJsonObject("execution")["remote_cache_download_duration_ms"].asLong >= 0)
            assertTrue(cold["id"] != warm["id"], "Each configuration-cache reuse needs a fresh build identity")
            for (report in listOf(cold, warm)) {
                val startedAt = Instant.parse(report["started_at"].asString).toEpochMilli()
                val finishedAt = startedAt + report["duration_ms"].asLong
                val metrics = report.getAsJsonArray("machine_metrics").map { it.asJsonObject }
                assertTrue(metrics.size >= 2, "A build must include monitoring boundary samples")
                val firstSampleAt = (metrics.first()["timestamp"].asDouble * 1000).roundToLong()
                val lastSampleAt = (metrics.last()["timestamp"].asDouble * 1000).roundToLong()
                assertTrue(firstSampleAt <= startedAt, "Monitoring started at $firstSampleAt after build origin $startedAt")
                assertTrue(lastSampleAt >= finishedAt, "Monitoring ended at $lastSampleAt before the build finished at $finishedAt; warm=${report === warm}")
                for (task in report.getAsJsonArray("tasks").map { it.asJsonObject }) {
                    val taskStart = Instant.parse(task["started_at"].asString).toEpochMilli()
                    assertTrue(taskStart >= startedAt, "Task must share the build duration origin")
                    assertTrue(taskStart + task["duration_ms"].asLong <= finishedAt)
                }
            }
            assertTrue(Instant.parse(warm["started_at"].asString) > Instant.parse(cold["started_at"].asString))

            val (_, uncached) = run("--no-build-cache")
            val executed = uncached.getAsJsonArray("tasks").map { it.asJsonObject }
                .first { it["task_path"].asString == ":app:compileJava" }
            assertEquals("executed", executed["outcome"].asString)
            assertEquals("not_requested", executed.getAsJsonObject("execution")["remote_cache_lookup_outcome"].asString)
            assertTrue(!executed["remote_cache_miss"].asBoolean)
            assertEquals("cacheable", executed.getAsJsonObject("execution")["cacheability"].asString)
            assertTrue(executed["cacheable"].asBoolean)

            val (_, unchanged) = run("--no-build-cache", "-x", "clean")
            val upToDate = unchanged.getAsJsonArray("tasks").map { it.asJsonObject }
                .first { it["task_path"].asString == ":app:compileJava" }
            assertEquals("up_to_date", upToDate["outcome"].asString)
            assertEquals("cacheable", upToDate.getAsJsonObject("execution")["cacheability"].asString)
            val clean = cold.getAsJsonArray("tasks").map { it.asJsonObject }
                .first { it["task_path"].asString == ":app:clean" }
            assertEquals("disabled", clean.getAsJsonObject("execution")["cacheability"].asString)

            File(directory, "settings.gradle").appendText("\nbuildCache { local { enabled = true; directory = file('local-cache') }; remote { enabled = false } }\n")
            run()
            val (localOutput, locallyCached) = run()
            val local = locallyCached.getAsJsonArray("tasks").map { it.asJsonObject }
                .first { it["task_path"].asString == ":app:compileJava" }
            assertEquals("local_hit", local["outcome"].asString, localOutput)
            assertEquals("not_requested", local.getAsJsonObject("execution")["remote_cache_lookup_outcome"].asString)
            assertTrue(!local["remote_cache_miss"].asBoolean)
        }
    }
    @Test
    fun `keeps identical task paths in composite builds distinct and records failure`() {
        val reports = LinkedBlockingQueue<JsonObject>()
        MockWebServer().use { server ->
            server.start()
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    if (request.path.orEmpty().endsWith("/gradle/builds")) {
                        val report = JsonParser.parseString(request.body.readUtf8()).asJsonObject
                        reports.add(report)
                        return MockResponse().setResponseCode(201).setBody("{\"id\":\"${report["id"].asString}\"}")
                    }
                    return MockResponse().setBody("{\"endpoints\":[\"${server.url("/")}\"]}")
                }
            }
            File(directory, "settings.gradle").writeText("""
                plugins { id 'dev.tuist' }
                tuist { project = 'test/telemetry'; url = '${server.url("/")}'; uploadInBackground = false; buildCache { enabled = false } }
                rootProject.name = 'root'
                includeBuild('included') { name = 'included&tools' }
            """.trimIndent())
            File(directory, "build.gradle").writeText("""
                tasks.register('compile') { doLast { println 'root compile' } }
                tasks.register('verify') {
                    dependsOn 'compile', gradle.includedBuild('included&tools').task(':compile')
                    doLast { throw new GradleException('expected fixture failure') }
                }
            """.trimIndent())
            File(directory, "included").mkdirs()
            File(directory, "included/settings.gradle").writeText("rootProject.name = 'included&tools'")
            File(directory, "included/build.gradle").writeText("tasks.register('compile') { doLast { println 'included compile' } }")
            val result = GradleRunner.create().withProjectDir(directory).withPluginClasspath()
                .withEnvironment(System.getenv().filterKeys { it !in setOf("TUIST_URL", "TUIST_CACHE_ENDPOINT") } + ("TUIST_TOKEN" to "test-only-token"))
                .withArguments("verify", "--configuration-cache", "--parallel", "--no-watch-fs", "--stacktrace").buildAndFail()
            val report = assertNotNull(reports.poll(20, TimeUnit.SECONDS), result.output)
            assertEquals("failure", report["status"].asString, result.output)
            val tasks = report.getAsJsonArray("tasks").map { it.asJsonObject }
            val compile = tasks.filter { it["task_path"].asString == ":compile" }
            assertEquals(setOf(":", ":included&tools"), compile.map { it.getAsJsonObject("execution")["build_path"].asString }.toSet())
            assertEquals("failed", tasks.first { it["task_path"].asString == ":verify" }["outcome"].asString)
        }
    }

}
