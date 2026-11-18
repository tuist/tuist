package dev.tuist.gradle

import org.jacoco.core.data.ExecutionData
import org.jacoco.core.data.ExecutionDataStore
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
        fun analysis() = ClassAnalysis(ClassIndex(listOf(classesDir)), repository, emptyMap(), emptySet())

        assertTrue(analysis().apply { measure(store) }.mismatchedClasses.isEmpty())

        store.put(ExecutionData(2L, "dev/tuist/demo/Pricing", booleanArrayOf(true)))
        assertEquals(setOf("dev/tuist/demo/Pricing"), analysis().apply { measure(store) }.mismatchedClasses)
    }

    @Test
    fun `lines become inclusive ranges`() {
        assertEquals(listOf(1, 3, 7, 7, 9, 10), GradleCoverage.ranges(setOf(10, 2, 1, 3, 7, 9)))
    }
}
