package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.gradle.testkit.runner.BuildResult
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TuistTestShardFunctionalTest {

    @TempDir
    lateinit var projectDir: File

    private lateinit var server: MockWebServer
    private val cacheEntries = ConcurrentHashMap<String, ByteArray>()
    private val shards = ConcurrentHashMap<Int, Map<String, Any>>()
    private val shardRequestPluginVersions = CopyOnWriteArrayList<String?>()

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.requestUrl?.encodedPath.orEmpty()
                val shardIndex = Regex("/tests/shards/shard-reference/(\\d+)$").find(path)?.groupValues?.get(1)
                return when {
                    path.startsWith("/api/cache/gradle/") && request.method == "PUT" -> {
                        cacheEntries[path] = request.body.readByteArray()
                        MockResponse().setResponseCode(201)
                    }
                    path.startsWith("/api/cache/gradle/") ->
                        cacheEntries[path]?.let { MockResponse().setBody(Buffer().write(it)) }
                            ?: MockResponse().setResponseCode(404)
                    shardIndex != null -> {
                        shardRequestPluginVersions.add(request.getHeader(PluginVersion.HEADER_NAME))
                        MockResponse().setResponseCode(200).setBody(Gson().toJson(shards.getValue(shardIndex.toInt())))
                    }
                    path.endsWith("/gradle/builds") ->
                        MockResponse().setResponseCode(201).setBody("""{"id":"build"}""")
                    else -> MockResponse().setResponseCode(200).setBody("{}")
                }
            }
        }
        server.start()
        writeProject()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `runs only the suites assigned to the shard in each project`() {
        shards[0] = assigned(mapOf(":app" to listOf("com.example.FooTest")))

        val result = runShard(0, "test")

        assertEquals(TaskOutcome.SUCCESS, result.task(":app:test")?.outcome, result.output)
        assertEquals(setOf("com.example.FooTest"), executedSuites("app"))
        assertEquals(TaskOutcome.SKIPPED, result.task(":lib:test")?.outcome, result.output)
    }

    @Test
    fun `does not reuse another shard's test results from the build cache`() {
        shards[0] = assigned(mapOf(":app" to listOf("com.example.FooTest"), ":lib" to listOf("com.example.LibTest")))
        shards[1] = assigned(mapOf(":app" to listOf("com.example.BarTest")))

        val first = runShard(0, "test")
        assertEquals(TaskOutcome.SUCCESS, first.task(":app:test")?.outcome, first.output)

        val second = runShard(1, "clean", "test")

        assertEquals(TaskOutcome.SUCCESS, second.task(":app:test")?.outcome, second.output)
        assertEquals(setOf("com.example.BarTest"), executedSuites("app"))
    }

    @Test
    fun `does not reuse a shard's test results in a build without sharding`() {
        shards[0] = assigned(mapOf(":app" to listOf("com.example.FooTest")))

        runShard(0, "test")
        val unsharded = run(emptyMap(), "clean", ":app:test")

        assertEquals(TaskOutcome.SUCCESS, unsharded.task(":app:test")?.outcome, unsharded.output)
        assertEquals(setOf("com.example.FooTest", "com.example.BarTest"), executedSuites("app"))
        assertFalse(unsharded.output.contains("Tuist: Test sharding active"), unsharded.output)
    }

    @Test
    fun `reuses a shard's own test results from the build cache`() {
        shards[0] = assigned(mapOf(":app" to listOf("com.example.FooTest")))

        runShard(0, "test")
        val rerun = runShard(0, "clean", "test")

        assertEquals(TaskOutcome.FROM_CACHE, rerun.task(":app:test")?.outcome, rerun.output)
        assertTrue(rerun.output.contains("Tuist: Test sharding active"), rerun.output)
    }

    @Test
    fun `sends the plugin version the server enables the catch-all final shard for`() {
        shards[0] = assigned(mapOf(":app" to listOf("com.example.FooTest")))

        runShard(0, "test")

        assertEquals(listOf(PluginVersion.current), shardRequestPluginVersions)
        assertTrue(PluginVersion.current != null)
    }

    @Test
    fun `catch-all shard runs every suite outside the other shards, including suites missing from history`() {
        shards[1] = catchAll(":app/com.example.FooTest")

        val result = runShard(1, "test")

        assertEquals(TaskOutcome.SUCCESS, result.task(":app:test")?.outcome, result.output)
        assertEquals(setOf("com.example.BarTest"), executedSuites("app"))
        assertEquals(TaskOutcome.SUCCESS, result.task(":lib:test")?.outcome, result.output)
        assertEquals(setOf("com.example.LibTest"), executedSuites("lib"))
    }

    @Test
    fun `catch-all shard of a plan without history runs every suite`() {
        shards[0] = catchAll()

        runShard(0, "test")

        assertEquals(setOf("com.example.FooTest", "com.example.BarTest"), executedSuites("app"))
        assertEquals(setOf("com.example.LibTest"), executedSuites("lib"))
    }

    @Test
    fun `catch-all shard does not reuse another shard's test results from the build cache`() {
        shards[0] = assigned(mapOf(":app" to listOf("com.example.FooTest")))
        shards[1] = catchAll(":app/com.example.FooTest")

        runShard(0, "test")
        val catchAll = runShard(1, "clean", "test")

        assertEquals(TaskOutcome.SUCCESS, catchAll.task(":app:test")?.outcome, catchAll.output)
        assertEquals(setOf("com.example.BarTest"), executedSuites("app"))
    }

    @Test
    fun `runs a nested class on the shard its outer class is assigned to`() {
        writeNestedTestClass()
        shards[0] = assigned(mapOf(":app" to listOf("com.example.OuterTest")))

        runShard(0, "test")

        assertEquals(setOf("com.example.OuterTest", "com.example.OuterTest\$Inner"), executedSuites("app"))
    }

    @Test
    fun `catch-all shard excludes the nested classes of a suite assigned to another shard`() {
        writeNestedTestClass()
        shards[1] = catchAll(":app/com.example.OuterTest")

        runShard(1, "test")

        assertEquals(setOf("com.example.FooTest", "com.example.BarTest"), executedSuites("app"))
    }

    private fun writeNestedTestClass() {
        val source = File(projectDir, "app/src/test/java/com/example/OuterTest.java")
        source.writeText(
            """
            package com.example;

            import org.junit.jupiter.api.Nested;
            import org.junit.jupiter.api.Test;

            public class OuterTest {
                @Test
                public void passes() {
                }

                @Nested
                class Inner {
                    @Test
                    public void passes() {
                    }
                }
            }
            """.trimIndent()
        )
    }

    private fun assigned(suites: Map<String, List<String>>): Map<String, Any> =
        mapOf(
            "download_urls" to emptyList<String>(),
            "modules" to suites.keys.toList(),
            "shard_plan_id" to UUID.randomUUID().toString(),
            "suites" to suites,
            "skip" to emptyList<String>()
        )

    private fun catchAll(vararg skip: String): Map<String, Any> =
        mapOf(
            "download_urls" to emptyList<String>(),
            "modules" to emptyList<String>(),
            "shard_plan_id" to UUID.randomUUID().toString(),
            "suites" to emptyMap<String, List<String>>(),
            "skip" to skip.toList()
        )

    private fun executedSuites(project: String): Set<String> =
        File(projectDir, "$project/build/test-results/test").listFiles().orEmpty()
            .map { it.name }
            .filter { it.startsWith("TEST-") && it.endsWith(".xml") }
            .map { it.removePrefix("TEST-").removeSuffix(".xml") }
            .toSet()

    private fun runShard(index: Int, vararg tasks: String): BuildResult =
        run(mapOf("TUIST_SHARD_INDEX" to index.toString(), "TUIST_SHARD_REFERENCE" to "shard-reference"), *tasks)

    private fun run(environment: Map<String, String>, vararg tasks: String): BuildResult =
        GradleRunner.create()
            .withProjectDir(projectDir)
            .withPluginClasspath()
            .withEnvironment(
                System.getenv().filterKeys { !it.startsWith("TUIST_") } + environment + mapOf(
                    "TUIST_URL" to server.url("/").toString().trimEnd('/'),
                    "TUIST_CACHE_ENDPOINT" to server.url("/").toString().trimEnd('/'),
                    "TUIST_TOKEN" to "test-token"
                )
            )
            .withArguments(tasks.toList() + listOf("--build-cache", "--no-watch-fs", "--stacktrace"))
            .build()

    private fun writeProject() {
        File(projectDir, "settings.gradle.kts").writeText(
            """
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
                uploadInBackground = false
            }

            buildCache { local { isEnabled = false } }

            rootProject.name = "shard-fixture"
            include(":app", ":lib")
            """.trimIndent()
        )
        File(projectDir, "build.gradle.kts").writeText(
            """
            subprojects {
                apply(plugin = "java")

                dependencies {
                    "testImplementation"(files(${junitClasspath()}))
                }

                tasks.withType<Test>().configureEach {
                    useJUnitPlatform()
                }
            }
            """.trimIndent()
        )
        writeTestClass("app", "FooTest")
        writeTestClass("app", "BarTest")
        writeTestClass("lib", "LibTest")
    }

    private fun writeTestClass(project: String, name: String) {
        val source = File(projectDir, "$project/src/test/java/com/example/$name.java")
        source.parentFile.mkdirs()
        source.writeText(
            """
            package com.example;

            import org.junit.jupiter.api.Test;

            public class $name {
                @Test
                public void passes() {
                }
            }
            """.trimIndent()
        )
    }

    // The fixture build has no repositories, so JUnit comes from the jars already on this
    // suite's own runtime classpath.
    private fun junitClasspath(): String =
        System.getProperty("java.class.path")
            .split(File.pathSeparator)
            .filter { it.contains("junit") || it.contains("opentest4j") || it.contains("apiguardian") }
            .joinToString(", ") { "\"${it.replace("\\", "\\\\")}\"" }
}
