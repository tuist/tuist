package dev.tuist.gradle

import com.google.gson.annotations.SerializedName
import org.gradle.api.Project
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.logging.Logging
import org.gradle.api.provider.Provider
import org.gradle.api.tasks.Classpath
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.testing.Test
import org.gradle.process.CommandLineArgumentProvider
import org.gradle.testing.jacoco.plugins.JacocoTaskExtension
import org.gradle.tooling.events.task.TaskFailureResult
import org.gradle.tooling.events.task.TaskFinishEvent
import org.gradle.tooling.events.task.TaskSkippedResult
import org.gradle.tooling.events.task.TaskSuccessResult
import org.jacoco.core.analysis.Analyzer
import org.jacoco.core.analysis.IClassCoverage
import org.jacoco.core.analysis.ICounter
import org.jacoco.core.analysis.ICoverageVisitor
import org.jacoco.core.data.ExecutionData
import org.jacoco.core.data.ExecutionDataReader
import org.jacoco.core.data.ExecutionDataStore
import org.jacoco.core.data.SessionInfoStore
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.EOFException
import java.io.File
import java.io.InputStream
import java.io.Serializable
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.TreeMap
import java.util.zip.ZipFile
import javax.inject.Inject

/**
 * Configuration for code coverage. When enabled, the plugin applies JaCoCo to every JVM project,
 * measures the code each test task ran, and reports it with the test run, together with which
 * files each test executed (test-scoped evidence) for the tests JUnit Platform runs.
 */
open class CoverageExtension {
    /**
     * Whether test runs measure and report code coverage. When null (default), coverage is off
     * unless the `TUIST_TEST_COVERAGE` environment variable turns it on.
     */
    var enabled: Boolean? = null
}

internal object CoverageSettings {
    const val ENVIRONMENT_VARIABLE = "TUIST_TEST_COVERAGE"

    /** The environment variable wins over the build's setting, so a CI job can turn coverage on or off. */
    fun enabled(environmentValue: String?, extensionValue: Boolean?): Boolean =
        when (environmentValue?.trim()?.lowercase()) {
            "1", "true", "yes" -> true
            "0", "false", "no" -> false
            else -> extensionValue ?: false
        }
}

/** What a test task needs measured, recorded when Gradle decides to run it or restore its outputs. */
data class CoverageTaskRecord(
    val taskPath: String,
    val module: String,
    /** Null when JaCoCo is off for the task, so its tests run unmeasured. */
    val execFile: File?,
    val evidenceDirectory: File,
    val classpath: List<File>,
    val testClassesDirs: List<File>,
    /** The task's `--tests` filters: the caller narrowed it. Build-script filters define the suite. */
    val commandLineFilters: List<String>,
    val failFast: Boolean
) : Serializable

/** How a test task ended, read from its completion event. */
enum class CoverageTaskOutcome {
    /** Its actions ran, whether its tests passed or failed. */
    EXECUTED,

    /** Up to date, or loaded from the build cache: its tests did not run, and its outputs, the execution data included, are those of the run that executed it. */
    RESTORED,

    /** It had no test classes. */
    NO_SOURCE,

    /** Skipped some other way, such as by `onlyIf` or a shard. */
    SKIPPED;

    companion object {
        fun of(event: TaskFinishEvent): CoverageTaskOutcome =
            when (val result = event.result) {
                is TaskSuccessResult -> if (result.isUpToDate || result.isFromCache) RESTORED else EXECUTED
                is TaskFailureResult -> EXECUTED
                is TaskSkippedResult -> if (result.skipMessage == "NO-SOURCE") NO_SOURCE else SKIPPED
                else -> SKIPPED
            }
    }
}

/**
 * Loads the listener jar into a test JVM, where the JUnit Platform finds it as a service, and
 * tells it where to write evidence. The jar is an input by content; the directory is local state,
 * so neither its path nor its contents reach the task's cache key.
 */
abstract class CoverageListenerArguments : CommandLineArgumentProvider {
    @get:Classpath
    abstract val listener: ConfigurableFileCollection

    @get:Internal
    abstract val directory: DirectoryProperty

    override fun asArguments(): Iterable<String> = listOf(
        "-javaagent:${listener.singleFile.absolutePath}",
        "-D$EVIDENCE_DIRECTORY_PROPERTY=${directory.get().asFile.absolutePath}"
    )

    companion object {
        const val EVIDENCE_DIRECTORY_PROPERTY = "tuist.coverage.evidence.dir"
    }
}

internal object CoverageListenerJar {
    private const val RESOURCE = "/dev/tuist/gradle/tuist-coverage-listener.jar"

    private val bytes: ByteArray? by lazy {
        CoverageListenerJar::class.java.getResourceAsStream(RESOURCE)?.use(InputStream::readBytes)
    }

    /** Where the jar lives under the Gradle user home, named by its content. */
    fun file(gradleUserHome: File): File? {
        val content = bytes ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(content).joinToString("") { "%02x".format(it) }
        return File(gradleUserHome, "caches/tuist/coverage-listener/${digest.take(16)}.jar")
    }

    /** Writes the jar when it is missing, such as on a configuration-cache hit after the Gradle user home was cleaned. */
    fun ensure(file: File) {
        if (file.isFile) return
        val content = bytes ?: return
        file.parentFile.mkdirs()
        val temporary = File.createTempFile("tuist-coverage-listener", ".jar", file.parentFile)
        temporary.writeBytes(content)
        Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }
}

internal object TestTaskCoverage {
    /**
     * The task's `--tests` patterns, which Gradle keeps apart from the build script's filters only
     * in its internal filter type. Unavailable, a narrowed run reads as a full one, as before.
     */
    private fun commandLineFilters(test: Test): List<String> =
        try {
            (test.filter as? org.gradle.api.internal.tasks.testing.filter.DefaultTestFilter)
                ?.commandLineIncludePatterns?.toList().orEmpty()
        } catch (_: LinkageError) {
            emptyList()
        }

    /** Applies JaCoCo to the JVM projects. A project that applies it itself keeps its own settings. */
    fun applyJacoco(project: Project) {
        project.pluginManager.withPlugin("java-base") { project.pluginManager.apply("jacoco") }
    }

    fun configure(
        task: Test,
        project: Project,
        module: String,
        insights: Provider<TuistTestInsightsService>
    ) {
        val listenerJar = CoverageListenerJar.file(project.gradle.gradleUserHomeDir)
        val evidenceDirectory = project.layout.buildDirectory.dir("tuist/coverage/${task.name}")
        // Read once the build script configured JaCoCo, which may happen after this runs.
        val execFile: Provider<File> = project.provider {
            task.extensions.findByType(JacocoTaskExtension::class.java)?.takeIf { it.isEnabled }?.destinationFile
        }
        val taskPath = task.path

        task.localState.register(evidenceDirectory)
        if (listenerJar != null) {
            CoverageListenerJar.ensure(listenerJar)
            val arguments = project.objects.newInstance(CoverageListenerArguments::class.java)
            arguments.listener.from(listenerJar)
            arguments.directory.set(evidenceDirectory)
            task.jvmArgumentProviders.add(arguments)
        }

        // Evaluated before Gradle decides whether to execute the task or restore its outputs, so
        // the test tasks that are up to date or come from the build cache are recorded too.
        task.onlyIf {
            val test = it as Test
            listenerJar?.let(CoverageListenerJar::ensure)
            insights.get().registerCoverageTask(
                CoverageTaskRecord(
                    taskPath = taskPath,
                    module = module,
                    execFile = execFile.orNull,
                    evidenceDirectory = evidenceDirectory.get().asFile,
                    classpath = test.classpath.files.toList(),
                    testClassesDirs = test.testClassesDirs.files.toList(),
                    commandLineFilters = commandLineFilters(test),
                    failFast = test.failFast
                )
            )
            true
        }
        task.doFirst {
            evidenceDirectory.get().asFile.deleteRecursively()
        }
    }
}

// --- Payloads ---

data class CoveragePayload(
    val tool: String,
    @SerializedName("tool_version") val toolVersion: String,
    val partial: Boolean,
    val files: List<CoverageFilePayload>?,
    @SerializedName("storage_key") val storageKey: String? = null
)

data class CoverageFilePayload(
    val path: String,
    @SerializedName("git_blob_id") val gitBlobId: String?,
    val targets: List<String>,
    @SerializedName("is_test") val isTest: Boolean,
    @SerializedName("covered_lines") val coveredLines: Int,
    @SerializedName("executable_lines") val executableLines: Int,
    @SerializedName("line_numbers") val lineNumbers: List<Int>,
    @SerializedName("execution_counts") val executionCounts: List<Int>,
    val functions: List<CoverageFunctionPayload>
)

data class CoverageFunctionPayload(
    val name: String,
    @SerializedName("line_number") val lineNumber: Int,
    @SerializedName("execution_count") val executionCount: Int,
    @SerializedName("covered_lines") val coveredLines: Int,
    @SerializedName("executable_lines") val executableLines: Int
)

data class CoverageEvidencePayload(
    val paths: List<String>,
    val scopes: List<CoverageEvidenceScope>,
    @SerializedName("overlapped_tests") val overlappedTests: List<CoverageOverlappedTest>,
    val status: String
)

data class CoverageEvidenceScope(
    val kind: String,
    val module: String,
    val suite: String,
    val name: String,
    val files: List<Int>,
    val lines: List<List<Int>>
)

data class CoverageOverlappedTest(val module: String, val suite: String, val name: String)

/** What a run reports about its coverage, beside its test results. */
data class CoverageResult(
    val coverage: CoveragePayload,
    val evidence: CoverageEvidencePayload?,
    val onlyTestIdentifiers: List<String>?,
    val skipTestIdentifiers: List<String>?
)

/** A test the run executed, by module, class and name, as test insights reports it. */
data class CoverageExecutedTest(val module: String, val suite: String?, val name: String)

// --- What a run measured and left out ---

/**
 * Turns the test tasks of one build into the run's coverage: the `run` scope from the JaCoCo
 * execution data of every test task that executed or was restored, `target`, `suite` and `test`
 * evidence from the tasks that executed, and what the run left out.
 *
 * A restored task's execution data is that of the run that executed it on the same inputs, its
 * classes included, so it counts as measured. Its evidence describes tests this run did not
 * execute and is not reported again: the run that executed them reported it.
 */
internal class GradleCoverage(
    private val repository: CoverageRepository,
    /** Each module's directory relative to the repository's root, `""` for the root. */
    private val moduleDirectories: Map<String, String>,
    private val records: Collection<CoverageTaskRecord>,
    private val outcomes: Map<String, CoverageTaskOutcome>,
    /** Every test task of the build and its module; null when the build cannot know them (Isolated Projects, configuration on demand). */
    private val testTasks: Map<String, String>?,
    private val excludedTaskNames: Collection<String>,
    private val executedTests: List<CoverageExecutedTest>,
    private val modulesWithFailures: Set<String>,
    private val sharded: Boolean
) {
    private val logger = Logging.getLogger(GradleCoverage::class.java)

    fun build(): CoverageResult {
        val measured = records.filter { outcomes[it.taskPath] in setOf(CoverageTaskOutcome.EXECUTED, CoverageTaskOutcome.RESTORED) }
        val executed = measured.filter { outcomes[it.taskPath] == CoverageTaskOutcome.EXECUTED }
        val testsByModule = executedTests.groupBy { it.module }
        val unexplained = mutableListOf<String>()

        val testRoots = measured.flatMap { it.testClassesDirs }.map { it.absoluteFile }.toSet()
        val classes = ClassIndex(measured.flatMap { it.classpath }.filter(repository::isOwnOutput).distinct())
        val analysis = ClassAnalysis(classes, repository, moduleDirectories, testRoots)

        val runStore = ExecutionDataStore()
        for (record in measured) {
            val exec = record.execFile
            when {
                exec == null -> {
                    if (outcomes[record.taskPath] == CoverageTaskOutcome.RESTORED || testsByModule[record.module].orEmpty().isNotEmpty()) {
                        unexplained += "${record.taskPath} ran its tests without JaCoCo"
                    }
                }
                exec.isFile -> readExecutionData(exec.readBytes(), runStore)
            }
        }
        val files = analysis.measure(runStore)
        if (analysis.mismatchedClasses.isNotEmpty()) {
            unexplained += "the execution data of ${analysis.mismatchedClasses.size} class(es) does not match the classes on the test classpath"
        }
        if (analysis.unreadableClasses.isNotEmpty()) {
            unexplained += "${analysis.unreadableClasses.size} class(es) could not be analyzed"
        }

        val narrowed = measured.filter { it.commandLineFilters.isNotEmpty() }.map { it.module }.toSet()
        for (record in measured) {
            if (record.commandLineFilters.isNotEmpty() && outcomes[record.taskPath] == CoverageTaskOutcome.RESTORED &&
                executed.none { it.module == record.module }
            ) {
                unexplained += "${record.taskPath} was restored with --tests filters, so which tests it ran is unknown"
            }
            if (record.failFast && record.module in modulesWithFailures) {
                unexplained += "${record.taskPath} stopped at its first failure"
            }
        }

        // A test task the build reached is part of the run, whatever its outcome: one its own
        // configuration skipped (disabled, `onlyIf`) is how the build defines its suite, as an
        // Xcode test plan's disabled tests are. Only the tasks the build never reached were left out.
        val ranModules = (records.filter { it.taskPath in outcomes }.map { it.module } +
            testTasks.orEmpty().filterKeys { it in outcomes }.values).toSet()
        // A shard runs what its plan assigned, which the server knows from the plan.
        val leftOut = if (sharded || testTasks == null) {
            emptyMap()
        } else {
            testTasks.entries.groupBy({ it.value }, { it.key }).filterKeys { it !in ranModules }
        }
        val (excluded, unselected) = leftOut.entries.partition { (_, paths) -> paths.all(::isExcluded) }
        val skipIdentifiers = excluded.map { it.key }.sorted()

        val onlyIdentifiers = if (narrowed.isNotEmpty() || unselected.isNotEmpty()) {
            measured.map { it.module }.distinct().sorted().flatMap { module ->
                if (module in narrowed) {
                    testsByModule[module].orEmpty().map { identifier(module, it.suite, it.name) }.distinct().sorted()
                } else {
                    listOf(identifier(module))
                }
            }
        } else {
            emptyList()
        }

        unexplained.forEach { logger.info("Tuist: The run's coverage is partial: $it.") }
        val partial = unexplained.isNotEmpty() || narrowed.isNotEmpty() || unselected.isNotEmpty() || excluded.isNotEmpty()

        return CoverageResult(
            coverage = CoveragePayload(
                tool = "jacoco",
                toolVersion = jacocoVersion(),
                partial = partial,
                files = repository.payload(files)
            ),
            evidence = evidence(executed, analysis),
            onlyTestIdentifiers = onlyIdentifiers.takeIf { it.isNotEmpty() },
            skipTestIdentifiers = skipIdentifiers.takeIf { it.isNotEmpty() }
        )
    }

    // `-x :app:test` names a task by its path; `-x test` names the tasks of that name everywhere.
    private fun isExcluded(taskPath: String): Boolean =
        taskPath in excludedTaskNames || taskPath.substringAfterLast(':') in excludedTaskNames

    private fun evidence(executed: List<CoverageTaskRecord>, analysis: ClassAnalysis): CoverageEvidencePayload? {
        val withAgent = executed.filter { it.execFile?.isFile == true }
        if (withAgent.isEmpty()) return null

        val scopes = mutableListOf<Pair<CoverageScopeKey, Map<String, Set<Int>>>>()
        val overlapped = linkedSetOf<CoverageOverlappedTest>()
        var failed = false

        for ((module, moduleRecords) in withAgent.groupBy { it.module }) {
            val target = ExecutionDataStore()
            moduleRecords.forEach { readExecutionData(it.execFile!!.readBytes(), target) }
            scopes += CoverageScopeKey("target", module, "", "") to analysis.executed(target)

            val segments = LinkedHashMap<CoverageScopeKey, ExecutionDataStore>()
            for (record in moduleRecords) {
                val files = record.evidenceDirectory.listFiles { file -> file.name.endsWith(".evidence") }.orEmpty().sortedBy { it.name }
                for (file in files) {
                    try {
                        EvidenceFile.read(file) { segment ->
                            when (segment) {
                                is EvidenceFile.Segment -> readExecutionData(
                                    segment.data,
                                    segments.getOrPut(CoverageScopeKey(segment.kind, module, segment.suite, segment.name)) { ExecutionDataStore() }
                                )
                                is EvidenceFile.Overlapped -> overlapped += CoverageOverlappedTest(module, segment.suite, segment.name)
                            }
                        }
                    } catch (e: Exception) {
                        logger.info("Tuist: The coverage evidence in ${file.name} could not be read: ${e.message}")
                        failed = true
                    }
                }
            }
            segments.forEach { (key, store) -> scopes += key to analysis.executed(store) }
        }

        val testScoped = scopes.any { it.first.kind != "target" }
        val paths = scopes.flatMap { it.second.keys }.distinct().sorted()
        val index = paths.withIndex().associate { it.value to it.index }
        return CoverageEvidencePayload(
            paths = paths,
            scopes = scopes.map { (key, files) ->
                val sorted = files.keys.sorted()
                CoverageEvidenceScope(
                    kind = key.kind,
                    module = key.module,
                    suite = key.suite,
                    name = key.name,
                    files = sorted.map { index.getValue(it) },
                    lines = sorted.map { ranges(files.getValue(it)) }
                )
            },
            // A test with a scope of its own in another process did not overlap there.
            overlappedTests = overlapped.filter { test ->
                scopes.none { it.first == CoverageScopeKey("test", test.module, test.suite, test.name) }
            },
            status = when {
                failed -> "failed"
                testScoped -> "collected"
                else -> "not_linked"
            }
        )
    }

    companion object {
        /**
         * A test identifier as the server parses it (`Module`, `Module/Suite/test`), each part
         * percent-encoded where it holds a `/` or a `%`, as parameterized test names can.
         */
        fun identifier(vararg parts: String?): String =
            parts.filterNotNull().joinToString("/") { it.replace("%", "%25").replace("/", "%2F") }

        /** Lines as inclusive ranges, flattened: `[3, 5, 9, 9]` is lines 3 to 5 and line 9. */
        fun ranges(lines: Set<Int>): List<Int> {
            val result = mutableListOf<Int>()
            for (line in lines.sorted()) {
                if (result.isNotEmpty() && result.last() == line - 1) result[result.lastIndex] = line else {
                    result += line
                    result += line
                }
            }
            return result
        }

        fun jacocoVersion(): String =
            try {
                org.jacoco.core.JaCoCo.VERSION
            } catch (_: Throwable) {
                "unknown"
            }

        fun readExecutionData(bytes: ByteArray, store: ExecutionDataStore) {
            val reader = ExecutionDataReader(ByteArrayInputStream(bytes))
            reader.setExecutionDataVisitor(store)
            reader.setSessionInfoVisitor(SessionInfoStore())
            reader.read()
        }
    }
}

internal data class CoverageScopeKey(val kind: String, val module: String, val suite: String, val name: String)

/** The records the listener writes in a test JVM (see `TuistCoverageListener`). */
internal object EvidenceFile {
    sealed class Record
    class Segment(val kind: String, val suite: String, val name: String, val data: ByteArray) : Record()
    class Overlapped(val suite: String, val name: String) : Record()

    fun read(file: File, visit: (Record) -> Unit) {
        DataInputStream(file.inputStream().buffered()).use { input ->
            while (true) {
                val type = try {
                    input.readUnsignedByte()
                } catch (_: EOFException) {
                    return
                }
                when (type) {
                    1 -> {
                        val kind = string(input)
                        val suite = string(input)
                        val name = string(input)
                        val data = ByteArray(input.readInt()).also(input::readFully)
                        if (kind == "test" || kind == "suite") visit(Segment(kind, suite, name, data))
                    }
                    2 -> visit(Overlapped(string(input), string(input)))
                    else -> throw IllegalStateException("unknown record type $type")
                }
            }
        }
    }

    private fun string(input: DataInputStream): String =
        String(ByteArray(input.readInt()).also(input::readFully), Charsets.UTF_8)
}

/** The class files of the repository's own classpath entries, directories and jars, by class name. */
internal class ClassIndex(roots: List<File>) {
    class Entry(val root: File, val bytes: ByteArray)

    val byName: Map<String, List<Entry>>

    init {
        val entries = mutableMapOf<String, MutableList<Entry>>()
        fun add(root: File, name: String, bytes: ByteArray) {
            if (name == "module-info" || name.endsWith("/module-info") || name.endsWith("package-info")) return
            entries.getOrPut(name) { mutableListOf() } += Entry(root, bytes)
        }
        for (root in roots) {
            when {
                root.isDirectory -> root.walkTopDown().filter { it.isFile && it.name.endsWith(".class") }.forEach {
                    add(root, it.relativeTo(root).invariantSeparatorsPath.removeSuffix(".class"), it.readBytes())
                }
                root.isFile && root.name.endsWith(".jar") -> try {
                    ZipFile(root).use { zip ->
                        zip.entries().asSequence()
                            .filter { !it.isDirectory && it.name.endsWith(".class") && !it.name.startsWith("META-INF/") }
                            .forEach { add(root, it.name.removeSuffix(".class"), zip.getInputStream(it).use(InputStream::readBytes)) }
                    }
                } catch (_: Exception) {
                    // Not a readable jar: nothing of it is measured.
                }
            }
        }
        byName = entries
    }
}

/** One source file's measured lines, merged over the classes compiled from it. */
internal class FileCoverage(val path: String, val target: String?, val isTest: Boolean) {
    /** Executable line → whether it ran. */
    val lines = TreeMap<Int, Boolean>()
    val functions = LinkedHashMap<Pair<String, Int>, CoverageFunctionPayload>()
}

/**
 * Runs JaCoCo's analysis over the repository's classes and maps each class to the source file it
 * was compiled from. JaCoCo records whether code ran, not how often, so every count is 0 or 1.
 */
internal class ClassAnalysis(
    private val classes: ClassIndex,
    private val repository: CoverageRepository,
    private val moduleDirectories: Map<String, String>,
    private val testRoots: Set<File>
) {
    val mismatchedClasses = sortedSetOf<String>()
    val unreadableClasses = sortedSetOf<String>()
    private val executedLinesCache = HashMap<String, Set<Int>>()

    /** Every class of the repository's classpath entries, with the lines the execution data covered. */
    fun measure(store: ExecutionDataStore): Map<String, FileCoverage> {
        val files = TreeMap<String, FileCoverage>()
        for ((name, entries) in classes.byName) {
            for (entry in entries) {
                analyze(entry, store) { coverage ->
                    // Classes without a repository file, such as those Spring AOT precompiles and
                    // Spring Data defines again at runtime, count for nothing, so a mismatch there is moot.
                    val file = locate(entry, coverage) ?: return@analyze
                    if (coverage.isNoMatch) mismatchedClasses += name
                    val measured = files.getOrPut(file.path) { file }
                    for (line in coverage.firstLine..coverage.lastLine) {
                        if (coverage.firstLine <= 0) break
                        val counter = coverage.getLine(line).instructionCounter
                        if (counter.totalCount == 0) continue
                        measured.lines.merge(line, counter.coveredCount > 0, Boolean::or)
                    }
                    for (method in coverage.methods) {
                        if (method.firstLine <= 0) continue
                        val row = CoverageFunctionPayload(
                            name = functionName(coverage.name, method.name, method.desc),
                            lineNumber = method.firstLine,
                            executionCount = if (method.methodCounter.coveredCount > 0) 1 else 0,
                            coveredLines = method.lineCounter.coveredCount,
                            executableLines = method.lineCounter.totalCount
                        )
                        measured.functions.merge(row.name to row.lineNumber, row) { a, b ->
                            if (b.coveredLines > a.coveredLines) b else a
                        }
                    }
                }
            }
        }
        return files
    }

    /** The lines of each repository file that a scope's execution data covered, by path. */
    fun executed(store: ExecutionDataStore): Map<String, Set<Int>> {
        val result = TreeMap<String, MutableSet<Int>>()
        for (data in store.contents) {
            if (!data.hasHits()) continue
            for (entry in classes.byName[data.name].orEmpty()) {
                val key = "${System.identityHashCode(entry)}:${probeKey(data)}"
                val cached = executedLinesCache[key]
                val path = pathOf(entry, data.name) ?: continue
                val lines = cached ?: run {
                    val single = ExecutionDataStore().apply { put(ExecutionData(data.id, data.name, data.probes.copyOf())) }
                    val covered = mutableSetOf<Int>()
                    analyze(entry, single) { coverage ->
                        if (coverage.isNoMatch || coverage.firstLine <= 0) return@analyze
                        for (line in coverage.firstLine..coverage.lastLine) {
                            if (coverage.getLine(line).instructionCounter.coveredCount > 0) covered += line
                        }
                    }
                    covered.also { executedLinesCache[key] = it }
                }
                if (lines.isNotEmpty()) result.getOrPut(path) { sortedSetOf() } += lines
            }
        }
        return result
    }

    private val paths = HashMap<Pair<Int, String>, String?>()

    private fun pathOf(entry: ClassIndex.Entry, name: String): String? =
        paths.getOrPut(System.identityHashCode(entry) to name) {
            var path: String? = null
            analyze(entry, ExecutionDataStore()) { coverage -> path = locate(entry, coverage)?.path }
            path
        }

    private fun analyze(entry: ClassIndex.Entry, store: ExecutionDataStore, visit: (IClassCoverage) -> Unit) {
        try {
            Analyzer(store, ICoverageVisitor { visit(it) }).analyzeClass(entry.bytes, entry.root.path)
        } catch (_: Exception) {
            unreadableClasses += entry.root.path
        }
    }

    private fun locate(entry: ClassIndex.Entry, coverage: IClassCoverage): FileCoverage? {
        val sourceFile = coverage.sourceFileName ?: return null
        val module = owner(entry.root)
        val path = repository.locate(coverage.packageName, sourceFile, module?.let { moduleDirectories[it] }) ?: return null
        return FileCoverage(path, module, entry.root.absoluteFile in testRoots)
    }

    private fun owner(root: File): String? {
        val relative = repository.relative(root) ?: return null
        return moduleDirectories.entries
            .filter { (_, directory) -> directory.isEmpty() || relative == directory || relative.startsWith("$directory/") }
            .maxByOrNull { it.value.length }
            ?.key
    }

    private fun probeKey(data: ExecutionData): String =
        "${data.id}:" + data.probes.joinToString("") { if (it) "1" else "0" }

    companion object {
        /** `Foo.bar(int, String)`, `Foo(int)` for a constructor, `Foo.static {...}` for a static initializer. */
        fun functionName(className: String, method: String, descriptor: String): String {
            val simple = className.substringAfterLast('/').replace('$', '.')
            val parameters = parameterTypes(descriptor).joinToString(", ")
            return when (method) {
                "<init>" -> "$simple($parameters)"
                "<clinit>" -> "$simple.static {...}"
                else -> "$simple.$method($parameters)"
            }
        }

        private fun parameterTypes(descriptor: String): List<String> {
            val types = mutableListOf<String>()
            var index = descriptor.indexOf('(') + 1
            while (index > 0 && index < descriptor.length && descriptor[index] != ')') {
                var dimensions = 0
                while (descriptor[index] == '[') {
                    dimensions++
                    index++
                }
                val type = when (val c = descriptor[index]) {
                    'L' -> {
                        val end = descriptor.indexOf(';', index)
                        descriptor.substring(index + 1, end).substringAfterLast('/').replace('$', '.').also { index = end }
                    }
                    else -> primitives[c] ?: c.toString()
                }
                types += type + "[]".repeat(dimensions)
                index++
            }
            return types
        }

        private val primitives = mapOf(
            'Z' to "boolean", 'B' to "byte", 'C' to "char", 'S' to "short",
            'I' to "int", 'J' to "long", 'F' to "float", 'D' to "double"
        )
    }
}

/**
 * The checkout the coverage is measured against: its root, its JVM source files and their blobs.
 * Only files Git knows (tracked, or untracked and not ignored) are reported, under their path
 * relative to the repository's root, so generated sources stay out.
 */
internal class CoverageRepository(val root: File, sourceFiles: Collection<String>, private val blobIds: (Collection<String>) -> Map<String, String>) {
    private val byName: Map<String, List<String>> = sourceFiles.groupBy { it.substringAfterLast('/') }

    /**
     * Whether a classpath entry is the repository's own: under its root, and not in a Gradle user
     * home or project cache a CI job keeps in the checkout, which holds the dependencies' jars.
     */
    fun isOwnOutput(file: File): Boolean = relative(file)?.split('/')?.contains(".gradle") == false

    fun relative(file: File): String? {
        val path = file.absoluteFile.normalize()
        val base = root.absoluteFile.normalize()
        return if (path.startsWith(base)) path.relativeTo(base).invariantSeparatorsPath else null
    }

    /**
     * The repository file a class was compiled from, by its package's directories and its source
     * file's name, preferring the class's own module. Kotlin does not require a file's directory
     * to match its package, so a file the module holds only once by that name also matches.
     */
    fun locate(packageName: String, sourceFile: String, moduleDirectory: String?): String? {
        val candidates = byName[sourceFile] ?: return null
        val suffix = if (packageName.isEmpty()) sourceFile else "$packageName/$sourceFile"
        fun inModule(path: String) = moduleDirectory != null && (moduleDirectory.isEmpty() || path.startsWith("$moduleDirectory/"))
        val matching = candidates.filter { it == suffix || it.endsWith("/$suffix") }
        matching.filter(::inModule).minOrNull()?.let { return it }
        if (matching.isNotEmpty()) return matching.min()
        return candidates.filter(::inModule).singleOrNull()
    }

    fun payload(files: Map<String, FileCoverage>): List<CoverageFilePayload> {
        val blobs = blobIds(files.keys)
        return files.values.map { file ->
            val numbers = file.lines.keys.toList()
            CoverageFilePayload(
                path = file.path,
                gitBlobId = blobs[file.path],
                targets = listOfNotNull(file.target),
                isTest = file.isTest,
                coveredLines = file.lines.values.count { it },
                executableLines = numbers.size,
                // Test code keeps its counts but not its lines: the server leaves it out of every figure.
                lineNumbers = if (file.isTest) emptyList() else numbers,
                executionCounts = if (file.isTest) emptyList() else file.lines.values.map { if (it) 1 else 0 },
                functions = if (file.isTest) emptyList() else file.functions.values.sortedWith(compareBy({ it.lineNumber }, { it.name }))
            )
        }
    }

    companion object {
        private val sourceExtensions = setOf("java", "kt", "groovy", "scala")

        /** Reads the checkout at [directory] with Git, or null when it is not a Git repository. */
        fun load(directory: File, runner: (File) -> GitRunner = { ProcessGitRunner(it) }): CoverageRepository? {
            val root = try {
                File(runner(directory).capture(listOf("rev-parse", "--show-toplevel")).trim())
            } catch (_: Exception) {
                return null
            }
            val git = runner(root)
            val files = try {
                git.capture(listOf("ls-files", "-z", "--cached", "--others", "--exclude-standard"))
                    .split('\u0000').filter { it.isNotEmpty() && it.substringAfterLast('.') in sourceExtensions }
            } catch (_: Exception) {
                return null
            }
            return CoverageRepository(root, files.distinct()) { paths -> blobIds(git, paths.toSet()) }
        }

        /** Each path's blob in the checkout: the index's, or the working tree's when it changed or is untracked. */
        private fun blobIds(git: GitRunner, paths: Set<String>): Map<String, String> =
            try {
                val indexed = git.capture(listOf("ls-files", "--stage", "-z")).split('\u0000').mapNotNull { entry ->
                    val meta = entry.substringBefore('\t', "")
                    val path = entry.substringAfter('\t', "")
                    val parts = meta.split(' ')
                    if (parts.size >= 2 && parts[0] != "160000" && path in paths) path to parts[1] else null
                }.toMap()
                val changed = (
                    git.capture(listOf("diff", "--name-only", "--diff-filter=d", "-z")) + "\u0000" +
                        git.capture(listOf("ls-files", "--others", "--exclude-standard", "-z"))
                    ).split('\u0000').filter { it.isNotEmpty() && it in paths }.distinct().sorted()
                val hashed = changed.chunked(500).flatMap { batch ->
                    batch.zip(git.capture(listOf("hash-object", "--") + batch).lines().filter { it.isNotBlank() })
                }
                indexed + hashed
            } catch (_: Exception) {
                emptyMap()
            }
    }
}

/**
 * Sends a run's coverage inline when it compresses to no more than the server's threshold, and
 * otherwise uploads it first and names the upload in the run, as the other clients do.
 */
internal class CoverageUploader(
    private val httpClient: TuistHttpClient,
    private val httpClients: TuistHttpClients,
    private val serverUrl: String,
    private val projectDir: File
) {
    private val gson = com.google.gson.Gson()

    fun attach(coverage: CoveragePayload, testRunId: String, config: CacheConfiguration): CoveragePayload {
        val files = coverage.files ?: return coverage
        val compressed = deflate(files.joinToString("\n") { gson.toJson(it) }.toByteArray(Charsets.UTF_8))
        if (compressed.size <= inlineThreshold(config)) return coverage

        val upload = request(config, "POST", "uploads", mapOf("test_run_id" to testRunId))
        val storageKey = upload?.get("storage_key")?.asString ?: throw java.io.IOException("the server returned no storage key")
        val uploadUrl = upload.get("upload_url")?.asString ?: throw java.io.IOException("the server returned no upload URL")
        httpClient.retrying("Coverage upload", replaySafe = true) {
            val connection = httpClients.openConnection(java.net.URI(uploadUrl), readTimeoutMs = 120_000)
            try {
                connection.requestMethod = "PUT"
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(compressed.size)
                connection.outputStream.use { it.write(compressed) }
                val status = connection.responseCode
                if (status !in 200..299) {
                    throw TuistRetry.statusFailure(connection, status) { java.io.IOException("the coverage upload failed with HTTP $status") }
                }
            } finally {
                connection.disconnect()
            }
        }
        return coverage.copy(files = null, storageKey = storageKey)
    }

    private fun inlineThreshold(config: CacheConfiguration): Int =
        try {
            request(config, "GET", "settings", null)?.get("inline_threshold_bytes")?.asInt ?: DEFAULT_INLINE_THRESHOLD
        } catch (_: Exception) {
            DEFAULT_INLINE_THRESHOLD
        }

    private fun request(config: CacheConfiguration, method: String, path: String, body: Any?): com.google.gson.JsonObject? {
        val baseUrl = ServerUrlResolver.resolve(serverUrl, projectDir).trimEnd('/')
        val url = java.net.URI(baseUrl).resolve("/api/projects/${config.accountHandle}/${config.projectHandle}/tests/coverage/$path")
        // An upload URL is minted for the run's id, so asking again returns the same key.
        return httpClient.retrying("Coverage request to $path", replaySafe = true) {
            val connection = httpClient.openConnection(url, config)
            try {
                connection.requestMethod = method
                connection.setRequestProperty("Accept", "application/json")
                if (body != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    java.io.OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { gson.toJson(body, it) }
                }
                when (val status = connection.responseCode) {
                    in 200..299 -> java.io.InputStreamReader(connection.inputStream, Charsets.UTF_8).use {
                        gson.fromJson(it, com.google.gson.JsonObject::class.java)
                    }
                    else -> throw TuistRetry.statusFailure(connection, status) {
                        java.io.IOException("the server responded to coverage/$path with HTTP $status")
                    }
                }
            } finally {
                connection.disconnect()
            }
        }
    }

    companion object {
        private const val DEFAULT_INLINE_THRESHOLD = 5_000_000

        /** Raw DEFLATE, which the server inflates. */
        fun deflate(data: ByteArray): ByteArray {
            val deflater = java.util.zip.Deflater(java.util.zip.Deflater.DEFAULT_COMPRESSION, true)
            return try {
                deflater.setInput(data)
                deflater.finish()
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (!deflater.finished()) output.write(buffer, 0, deflater.deflate(buffer))
                output.toByteArray()
            } finally {
                deflater.end()
            }
        }
    }
}

/**
 * Tells Tuist that every run of a commit that measures coverage has reported, which the runs
 * alone cannot show. The commit's coverage is then complete and joins its branch's trend. Run it
 * in a final pipeline job that depends on every job that tests with coverage.
 *
 *     ./gradlew tuistCoverageComplete [-Ptuist.coverage.commit=SHA]
 *
 * The commit defaults to the one test runs report: `GIT_COMMIT`, or the checkout's `HEAD`.
 */
abstract class TuistCoverageCompleteTask : org.gradle.api.DefaultTask() {
    @get:org.gradle.api.tasks.Input
    abstract val serverUrl: org.gradle.api.provider.Property<String>

    @get:org.gradle.api.tasks.Input
    @get:org.gradle.api.tasks.Optional
    abstract val tuistProject: org.gradle.api.provider.Property<String>

    @get:org.gradle.api.tasks.Input
    abstract val useEnvironmentProxy: org.gradle.api.provider.Property<Boolean>

    @get:org.gradle.api.tasks.Input
    @get:org.gradle.api.tasks.Optional
    abstract val commitSha: org.gradle.api.provider.Property<String>

    @get:Internal
    abstract val rootDirectory: DirectoryProperty

    init {
        outputs.upToDateWhen { false }
    }

    @org.gradle.api.tasks.TaskAction
    fun complete() {
        val sha = commitSha.orNull?.takeIf { it.isNotBlank() }
            ?: throw org.gradle.api.GradleException("Tuist: The commit is unknown: pass -Ptuist.coverage.commit=<sha> or run inside a Git checkout.")
        val httpClients = TuistHttpClients(useEnvironmentProxy = useEnvironmentProxy.get())
        val provider = ServerConfigurationProvider(
            project = tuistProject.orNull,
            serverUrl = serverUrl.get(),
            projectDir = rootDirectory.get().asFile,
            httpClients = httpClients
        )
        val client = TuistHttpClient(provider, httpClients)
        val short = sha.take(7)
        val coverage = try {
            client.execute { config ->
                val url = provider.resolvedServerUrl
                    .resolve("/api/projects/${config.accountHandle}/${config.projectHandle}/tests/coverage/commits/$sha/complete")
                // Signalling again changes nothing.
                client.retrying("Coverage completion", replaySafe = true) {
                    val connection = client.openConnection(url, config)
                    try {
                        connection.requestMethod = "POST"
                        connection.doOutput = true
                        connection.setRequestProperty("Content-Type", "application/json")
                        connection.outputStream.use { it.write("{}".toByteArray()) }
                        when (val status = connection.responseCode) {
                            in 200..299 -> java.io.InputStreamReader(connection.inputStream, Charsets.UTF_8).use {
                                com.google.gson.Gson().fromJson(it, com.google.gson.JsonObject::class.java)
                                    ?.get("coverage")?.takeIf { value -> !value.isJsonNull }?.asString
                            }
                            java.net.HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                            else -> throw TuistRetry.statusFailure(connection, status) {
                                java.io.IOException("the server responded with HTTP $status")
                            }
                        }
                    } finally {
                        connection.disconnect()
                    }
                }
            }
        } catch (e: Exception) {
            throw org.gradle.api.GradleException("Tuist: Could not mark the coverage of commit $short complete: ${e.message}", e)
        }
        if (coverage != null) {
            logger.lifecycle("Tuist: Coverage of commit $short is complete: $coverage%.")
        } else {
            logger.lifecycle("Tuist: No run of commit $short has reported coverage yet. Its coverage is marked complete once one does.")
        }
    }
}
