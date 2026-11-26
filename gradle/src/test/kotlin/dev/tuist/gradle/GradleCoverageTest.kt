package dev.tuist.gradle

import org.jacoco.core.data.ExecutionData
import org.jacoco.core.data.ExecutionDataStore
import org.jacoco.core.internal.data.CRC64
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.objectweb.asm.ClassWriter
import org.objectweb.asm.Label
import org.objectweb.asm.Opcodes
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** What a run says it left out, for the runs a functional build would be costly to set up. */
class GradleCoverageTest {

    @TempDir
    lateinit var tempDir: File

    private fun record(path: String, module: String, filters: List<String> = emptyList(), failFast: Boolean = false) =
        CoverageTaskRecord(
            taskPath = path,
            module = module,
            execFile = File(tempDir, "${module.trim(':')}.exec"),
            evidenceDirectory = File(tempDir, "evidence"),
            classpath = emptyList(),
            testClassesDirs = emptyList(),
            commandLineFilters = filters,
            failFast = failFast
        )

    private fun coverage(
        records: List<CoverageTaskRecord>,
        outcomes: Map<String, CoverageTaskOutcome>,
        testTasks: Map<String, String>? = mapOf(":core:test" to ":core", ":app:test" to ":app"),
        executedTests: List<CoverageExecutedTest> = emptyList(),
        failures: Set<String> = emptySet(),
        sharded: Boolean = false
    ) = GradleCoverage(
        repository = CoverageRepository(tempDir, emptyList()) { emptyMap() },
        moduleDirectories = mapOf(":core" to "core", ":app" to "app"),
        records = records,
        outcomes = outcomes,
        compiledSources = emptyMap(),
        testTasks = testTasks,
        excludedTaskNames = emptyList(),
        executedTests = executedTests,
        modulesWithFailures = failures,
        sharded = sharded
    ).build()

    @Test
    fun `a shard leaves out what its plan assigned elsewhere without saying so`() {
        val result = coverage(listOf(record(":core:test", ":core")), mapOf(":core:test" to CoverageTaskOutcome.EXECUTED), sharded = true)

        assertFalse(result.coverage.partial)
        assertNull(result.onlyTestIdentifiers)
        assertNull(result.skipTestIdentifiers)
    }

    @Test
    fun `the same run unsharded names the project it ran`() {
        val result = coverage(listOf(record(":core:test", ":core")), mapOf(":core:test" to CoverageTaskOutcome.EXECUTED))

        assertTrue(result.coverage.partial)
        assertEquals(listOf(":core"), result.onlyTestIdentifiers)
    }

    @Test
    fun `a test task without test sources ran its whole suite`() {
        val result = coverage(
            listOf(record(":core:test", ":core"), record(":app:test", ":app")),
            mapOf(":core:test" to CoverageTaskOutcome.EXECUTED, ":app:test" to CoverageTaskOutcome.NO_SOURCE)
        )

        assertFalse(result.coverage.partial)
        assertNull(result.onlyTestIdentifiers)
    }

    @Test
    fun `a run that stopped at its first failure is partial and names nothing`() {
        val records = listOf(record(":core:test", ":core", failFast = true), record(":app:test", ":app"))
        val outcomes = mapOf(":core:test" to CoverageTaskOutcome.EXECUTED, ":app:test" to CoverageTaskOutcome.EXECUTED)

        assertTrue(coverage(records, outcomes, failures = setOf(":core")).coverage.partial)
        // Without a failure, fail-fast left nothing out.
        assertFalse(coverage(records, outcomes).coverage.partial)
    }

    @Test
    fun `a task restored with --tests filters ran tests nobody can name`() {
        val result = coverage(
            listOf(record(":core:test", ":core", filters = listOf("*CalcTest")), record(":app:test", ":app")),
            mapOf(":core:test" to CoverageTaskOutcome.RESTORED, ":app:test" to CoverageTaskOutcome.EXECUTED)
        )

        assertTrue(result.coverage.partial)
        assertEquals(listOf(":app"), result.onlyTestIdentifiers)
    }

    @Test
    fun `a narrowed run names its tests with their slashes and percent signs encoded`() {
        val result = coverage(
            listOf(record(":core:test", ":core", filters = listOf("*CalcTest")), record(":app:test", ":app")),
            mapOf(":core:test" to CoverageTaskOutcome.EXECUTED, ":app:test" to CoverageTaskOutcome.EXECUTED),
            executedTests = listOf(CoverageExecutedTest(":core", "dev.CalcTest", "[1] a/b 50%"))
        )

        assertEquals(listOf(":app", ":core/dev.CalcTest/[1] a%2Fb 50%25"), result.onlyTestIdentifiers)
    }

    @Test
    fun `a build that cannot list its test tasks names nothing it left out`() {
        val result = coverage(listOf(record(":core:test", ":core")), mapOf(":core:test" to CoverageTaskOutcome.EXECUTED), testTasks = null)

        assertFalse(result.coverage.partial)
        assertNull(result.onlyTestIdentifiers)
    }

    @Test
    fun `stale execution data counts only for classes compiled from the repository's files`() {
        val classesDir = File(tempDir, "build/classes").apply { mkdirs() }
        fun writeClass(name: String, sourceFile: String?) {
            val writer = ClassWriter(0)
            writer.visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC, name, null, "java/lang/Object", null)
            sourceFile?.let { writer.visitSource(it, null) }
            writer.visitMethod(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC, "run", "()V", null, null).apply {
                visitCode()
                val start = Label()
                visitLabel(start)
                visitLineNumber(3, start)
                visitInsn(Opcodes.RETURN)
                visitMaxs(0, 0)
                visitEnd()
            }
            writer.visitEnd()
            File(classesDir, "$name.class").apply { parentFile.mkdirs() }.writeBytes(writer.toByteArray())
        }
        // Spring AOT precompiles accessors like this one, and Spring Data defines them again at runtime.
        writeClass("dev/tuist/demo/Owner__Accessor_cj2ue3", sourceFile = null)
        writeClass("dev/tuist/demo/Pricing", sourceFile = "Pricing.java")
        val store = ExecutionDataStore().apply {
            put(ExecutionData(1L, "dev/tuist/demo/Owner__Accessor_cj2ue3", booleanArrayOf(true)))
        }
        val repository = CoverageRepository(tempDir, listOf("core/src/main/java/dev/tuist/demo/Pricing.java")) { emptyMap() }
        fun analysis() = ClassAnalysis(ClassIndex(listOf(classesDir)), repository, emptyMap(), emptySet(), emptyMap())

        assertTrue(analysis().apply { measure(store) }.mismatchedClasses.isEmpty())

        store.put(ExecutionData(2L, "dev/tuist/demo/Pricing", booleanArrayOf(true)))
        assertEquals(setOf("dev/tuist/demo/Pricing"), analysis().apply { measure(store) }.mismatchedClasses)
    }

    @Test
    fun `classes that share a name across classpath entries are not mismatched when the execution data matches one of them`() {
        fun writeClass(dir: File, name: String, sourceFile: String, line: Int): ByteArray {
            val writer = ClassWriter(0)
            writer.visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC, name, null, "java/lang/Object", null)
            writer.visitSource(sourceFile, null)
            writer.visitMethod(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC, "run", "()V", null, null).apply {
                visitCode()
                val start = Label()
                visitLabel(start)
                visitLineNumber(line, start)
                visitInsn(Opcodes.RETURN)
                visitMaxs(0, 0)
                visitEnd()
            }
            writer.visitEnd()
            return writer.toByteArray().also { File(dir, "$name.class").apply { parentFile.mkdirs() }.writeBytes(it) }
        }
        val feature = File(tempDir, "feature/build/classes").apply { mkdirs() }
        val stub = File(tempDir, "feature-stub/build/classes").apply { mkdirs() }
        val main = File(tempDir, "core/build/classes/main").apply { mkdirs() }
        val test = File(tempDir, "core/build/classes/test").apply { mkdirs() }
        // A stub module redefines a feature module's class; only the feature's tests load it.
        val real = writeClass(feature, "dev/tuist/feature/Checkout", "Checkout.kt", 3)
        writeClass(stub, "dev/tuist/feature/Checkout", "Checkout.kt", 4)
        // A test source set shadows a main class; the test JVM loads the test copy.
        writeClass(main, "dev/tuist/core/Clock", "Clock.kt", 3)
        val shadow = writeClass(test, "dev/tuist/core/Clock", "Clock.kt", 5)
        // A test stand-in for a library class that another test JVM loads from the library.
        writeClass(test, "com/library/Logger", "Logger.kt", 3)
        val repository = CoverageRepository(
            tempDir,
            listOf(
                "feature/src/main/kotlin/dev/tuist/feature/Checkout.kt",
                "feature-stub/src/main/kotlin/dev/tuist/feature/Checkout.kt",
                "core/src/main/kotlin/dev/tuist/core/Clock.kt",
                "core/src/test/kotlin/dev/tuist/core/Clock.kt",
                "core/src/test/kotlin/com/library/Logger.kt"
            )
        ) { emptyMap() }
        val analysis = ClassAnalysis(
            ClassIndex(listOf(feature, stub, main, test)),
            repository,
            mapOf(":feature" to "feature", ":feature-stub" to "feature-stub", ":core" to "core"),
            setOf(test.absoluteFile),
            emptyMap()
        )
        val store = ExecutionDataStore().apply {
            put(ExecutionData(CRC64.classId(real), "dev/tuist/feature/Checkout", booleanArrayOf(true)))
            put(ExecutionData(CRC64.classId(shadow), "dev/tuist/core/Clock", booleanArrayOf(true)))
            put(ExecutionData(42L, "com/library/Logger", booleanArrayOf(true)))
        }

        val files = analysis.measure(store)

        assertEquals(emptySet<String>(), analysis.mismatchedClasses)
        assertEquals(mapOf(3 to true), files["feature/src/main/kotlin/dev/tuist/feature/Checkout.kt"]?.lines?.toMap())
    }

    @Test
    fun `a repository stand-in for a dependency's class is not mismatched by the dependency's own execution data`() {
        fun classBytes(name: String, sourceFile: String, line: Int): ByteArray {
            val writer = ClassWriter(0)
            writer.visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC, name, null, "java/lang/Object", null)
            writer.visitSource(sourceFile, null)
            writer.visitMethod(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC, "run", "()V", null, null).apply {
                visitCode()
                val start = Label()
                visitLabel(start)
                visitLineNumber(line, start)
                visitInsn(Opcodes.RETURN)
                visitMaxs(0, 0)
                visitEnd()
            }
            writer.visitEnd()
            return writer.toByteArray()
        }
        // A test-support module's main source set stands in for a framework class, which
        // Robolectric loads from the framework in other tests.
        val support = File(tempDir, "support/build/classes").apply { mkdirs() }
        File(support, "android/content/Intent.class").apply { parentFile.mkdirs() }
            .writeBytes(classBytes("android/content/Intent", "Intent.kt", 3))
        File(support, "dev/tuist/demo/Pricing.class").apply { parentFile.mkdirs() }
            .writeBytes(classBytes("dev/tuist/demo/Pricing", "Pricing.kt", 3))
        val framework = File(tempDir, ".gradle/caches/android.jar").apply { parentFile.mkdirs() }
        val real = classBytes("android/content/Intent", "Intent.java", 40)
        java.util.zip.ZipOutputStream(framework.outputStream()).use { zip ->
            zip.putNextEntry(java.util.zip.ZipEntry("android/content/Intent.class"))
            zip.write(real)
            zip.closeEntry()
        }
        val repository = CoverageRepository(
            tempDir,
            listOf("support/src/main/kotlin/android/content/Intent.kt", "support/src/main/kotlin/dev/tuist/demo/Pricing.kt")
        ) { emptyMap() }
        val analysis = ClassAnalysis(
            ClassIndex(listOf(support)), repository, mapOf(":support" to "support"), emptySet(), emptyMap(),
            dependencies = listOf(support, framework)
        )
        val store = ExecutionDataStore().apply {
            put(ExecutionData(CRC64.classId(real), "android/content/Intent", booleanArrayOf(true)))
            // Data no class on the classpath explains is still stale.
            put(ExecutionData(7L, "dev/tuist/demo/Pricing", booleanArrayOf(true)))
        }

        analysis.measure(store)

        assertEquals(setOf("dev/tuist/demo/Pricing"), analysis.mismatchedClasses)
    }

    @Test
    fun `includes name the repository's classes one by one in packages a dependency shares`() {
        File(tempDir, ".git").mkdirs()
        val classes = File(tempDir, "support/build/classes").apply { mkdirs() }
        for (name in listOf(
            "dev/tuist/demo/Pricing", "dev/tuist/demo/model/Item",
            "android/content/Intent", "android/content/Intent\$Builder", "android/content/res/Theme",
            "com/vendor/Shim", "Main"
        )) {
            File(classes, "$name.class").apply { parentFile.mkdirs() }.writeBytes(byteArrayOf())
        }
        val framework = File(tempDir, ".gradle/caches/android.jar").apply { parentFile.mkdirs() }
        java.util.zip.ZipOutputStream(framework.outputStream()).use { zip ->
            for (name in listOf("android/content/Intent.class", "android/content/Context.class", "com/vendor/sdk/Client.class")) {
                zip.putNextEntry(java.util.zip.ZipEntry(name))
                zip.closeEntry()
            }
        }

        assertEquals(
            listOf(
                // `com.vendor.*` would reach the vendor's `com.vendor.sdk`.
                "Main",
                "android.content.Intent",
                "android.content.Intent\$Builder",
                "android.content.res.*",
                "com.vendor.Shim",
                "dev.tuist.demo.*"
            ),
            TestTaskCoverage.repositoryIncludes(tempDir, listOf(classes, framework))
        )
        // Without the dependency, packages cover their subpackages as before.
        assertEquals(
            listOf("Main", "android.content.*", "com.vendor.*", "dev.tuist.demo.*"),
            TestTaskCoverage.repositoryIncludes(tempDir, listOf(classes))
        )
    }

    @Test
    fun `a partial run says why`() {
        val stopped = coverage(
            listOf(record(":core:test", ":core", failFast = true, filters = listOf("*CalcTest"))),
            mapOf(":core:test" to CoverageTaskOutcome.EXECUTED),
            failures = setOf(":core")
        )
        assertEquals(
            listOf(
                ":core:test stopped at its first failure",
                "--tests narrowed the tests of :core",
                "the build did not run the tests of :app (:app:test)"
            ),
            stopped.partialReasons
        )

        val excluded = GradleCoverage(
            repository = CoverageRepository(tempDir, emptyList()) { emptyMap() },
            moduleDirectories = mapOf(":core" to "core", ":app" to "app"),
            records = listOf(record(":core:test", ":core")),
            outcomes = mapOf(":core:test" to CoverageTaskOutcome.EXECUTED),
            compiledSources = emptyMap(),
            testTasks = mapOf(":core:test" to ":core", ":app:test" to ":app"),
            excludedTaskNames = listOf(":app:test"),
            executedTests = emptyList(),
            modulesWithFailures = emptySet(),
            sharded = false
        ).build()
        assertEquals(listOf("-x excluded the tests of :app"), excluded.partialReasons)

        val full = coverage(
            listOf(record(":core:test", ":core"), record(":app:test", ":app")),
            mapOf(":core:test" to CoverageTaskOutcome.EXECUTED, ":app:test" to CoverageTaskOutcome.EXECUTED)
        )
        assertEquals(emptyList(), full.partialReasons)
    }

    @Test
    fun `lines become inclusive ranges`() {
        assertEquals(listOf(1, 3, 7, 7, 9, 10), GradleCoverage.ranges(setOf(10, 2, 1, 3, 7, 9)))
    }
}
