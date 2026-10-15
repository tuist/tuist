package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GitHistoryReaderTest {

    @TempDir
    lateinit var tempDir: File

    private val fixture = GitRepositoryFixture()

    /**
     * A bare origin whose `feature` branch forked from `main` at [forkPoint], after which `main`
     * moved on to [mainHead].
     */
    private data class Origin(
        val url: String,
        val firstCommit: String,
        val forkPoint: String,
        val feature: String,
        val mainParent: String,
        val mainHead: String
    )

    private fun origin(): Origin {
        val seed = fixture.init(File(tempDir, "seed"))
        val first = fixture.commit(seed, "A1")
        fixture.commit(seed, "A2")
        val forkPoint = fixture.commit(seed, "A3")
        fixture.git(seed, "checkout", "-q", "-b", "feature")
        val feature = fixture.commit(seed, "F1")
        fixture.git(seed, "checkout", "-q", "main")
        fixture.commit(seed, "M1")
        val mainParent = fixture.commit(seed, "M2")
        val mainHead = fixture.commit(seed, "M3")
        val bare = File(tempDir, "origin.git")
        fixture.git(tempDir, "clone", "-q", "--bare", seed.absolutePath, bare.absolutePath)
        return Origin("file://${bare.absolutePath}", first, forkPoint, feature, mainParent, mainHead)
    }

    private fun clone(origin: Origin, vararg options: String): File {
        val checkout = File(tempDir, "checkout")
        fixture.git(tempDir, "clone", "-q", *options, origin.url, checkout.absolutePath)
        return checkout
    }

    private class RecordingGitRunner(private val delegate: GitRunner) : GitRunner {
        val fetches = mutableListOf<List<String>>()

        override fun capture(args: List<String>): String = delegate.capture(args)

        override fun fetch(args: List<String>, timeoutMillis: Long): FetchOutcome {
            fetches += args
            return delegate.fetch(args, timeoutMillis)
        }
    }

    private fun reader(checkout: File): Pair<GitHistoryReader, RecordingGitRunner> {
        val runner = RecordingGitRunner(ProcessGitRunner(checkout, environment = fixture.environment))
        return GitHistoryReader(runner, checkout) to runner
    }

    @Test
    fun `finds the merge base of a full clone without fetching`() {
        val origin = origin()
        val checkout = clone(origin, "--branch", "feature")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.feature, "main", GitHistoryLimits())

        assertEquals("sha1", history.objectFormat)
        assertEquals(origin.feature, history.headSha)
        assertEquals("main", history.baseBranch)
        assertEquals(origin.forkPoint, history.mergeBaseSha)
        assertEquals(origin.mainHead, history.baseHeadSha)
        assertNull(history.fallbackReason)
        assertTrue(runner.fetches.isEmpty())
        assertEquals(7, history.commits.size)
        assertEquals(origin.mainHead, history.commits.first().sha)
        val bySha = history.commits.associateBy { it.sha }
        assertEquals(listOf(origin.forkPoint), bySha.getValue(origin.feature).parents)
        assertEquals(emptyList(), bySha.getValue(origin.firstCommit).parents)
        assertEquals(fixture.committedAt(checkout, origin.feature), bySha.getValue(origin.feature).committedAt)
    }

    @Test
    fun `fetches the base branch and deepens a shallow clone until the merge base is found`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--branch", "feature")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.feature, "main", GitHistoryLimits())

        assertEquals(origin.forkPoint, history.mergeBaseSha)
        assertEquals(origin.mainHead, history.baseHeadSha)
        assertNull(history.fallbackReason)
        assertEquals(
            listOf("fetch", "--no-tags", "--filter=blob:none", "--depth=1", "origin", "+main:refs/remotes/origin/main"),
            runner.fetches[0]
        )
        assertEquals(
            listOf("fetch", "--no-tags", "--filter=blob:none", "--deepen=50", "origin", "+main:refs/remotes/origin/main"),
            runner.fetches[1]
        )
        assertEquals(2, runner.fetches.size)
        val bySha = history.commits.associateBy { it.sha }
        assertEquals(listOf(origin.forkPoint), bySha.getValue(origin.feature).parents)
        assertEquals(listOf(origin.mainParent), bySha.getValue(origin.mainHead).parents)
    }

    @Test
    fun `restores the parents of a shallow clone's boundary commits`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--branch", "main")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.mainHead, null, GitHistoryLimits(unshallow = false))

        assertTrue(fixture.isShallow(checkout))
        assertEquals(
            listOf(GitHistoryCommit(origin.mainHead, listOf(origin.mainParent), fixture.committedAt(checkout, origin.mainHead))),
            history.commits
        )
        assertEquals("no base branch is known", history.fallbackReason)
        assertTrue(runner.fetches.isEmpty())
    }

    @Test
    fun `never fetches a missing base branch when unshallowing is disabled`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--branch", "feature")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.feature, "main", GitHistoryLimits(unshallow = false))

        assertNull(history.mergeBaseSha)
        assertNull(history.baseHeadSha)
        assertEquals("the base branch main is not in the checkout and fetching it is disabled", history.fallbackReason)
        assertTrue(runner.fetches.isEmpty())
        assertFalse(fixture.hasRef(checkout, "refs/remotes/origin/main"))
        assertEquals(listOf(origin.feature), history.commits.map { it.sha })
    }

    @Test
    fun `reads the base branch the checkout has without deepening when unshallowing is disabled`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--no-single-branch", "--branch", "feature")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.feature, "main", GitHistoryLimits(unshallow = false))

        assertNull(history.mergeBaseSha)
        assertEquals(origin.mainHead, history.baseHeadSha)
        assertEquals(
            "shallow clone: the merge base with main is not in the checkout and deepening it is disabled",
            history.fallbackReason
        )
        assertTrue(runner.fetches.isEmpty())
        val bySha = history.commits.associateBy { it.sha }
        assertEquals(setOf(origin.feature, origin.mainHead), bySha.keys)
        assertEquals(listOf(origin.forkPoint), bySha.getValue(origin.feature).parents)
        assertEquals(listOf(origin.mainParent), bySha.getValue(origin.mainHead).parents)
    }

    @Test
    fun `reports a base branch the remote lacks`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--branch", "feature")
        val (reader, _) = reader(checkout)

        val history = reader.read(origin.feature, "release", GitHistoryLimits())

        assertNull(history.mergeBaseSha)
        assertNull(history.baseHeadSha)
        assertEquals("the base branch release is not in the checkout and could not be fetched", history.fallbackReason)
        assertEquals(listOf(GitHistoryCommit(origin.feature, listOf(origin.forkPoint), fixture.committedAt(checkout, origin.feature))), history.commits)
    }

    @Test
    fun `isRepository tells a checkout from a plain directory`() {
        val repository = fixture.init(File(tempDir, "repository"))
        val plain = File(tempDir, "plain").apply { mkdirs() }

        assertTrue(GitHistoryReader(ProcessGitRunner(repository, environment = fixture.environment), repository).isRepository())
        assertFalse(GitHistoryReader(ProcessGitRunner(plain, environment = fixture.environment), plain).isRepository())
    }

    /** A shallow checkout whose merge base is never found, with the base branch present. */
    private class ScriptedGitRunner(
        private val baseBranchPresent: Boolean = true,
        private val fetchOutcome: (List<String>) -> FetchOutcome = { FetchOutcome.SUCCEEDED },
        private val onFetch: () -> Unit = {}
    ) : GitRunner {
        val fetches = mutableListOf<List<String>>()
        val timeouts = mutableListOf<Long>()

        override fun capture(args: List<String>): String = when {
            args == listOf("rev-parse", "--show-object-format") -> "sha1\n"
            args == listOf("rev-parse", "--is-shallow-repository") -> "true\n"
            args.take(3) == listOf("rev-parse", "--verify", "--quiet") && baseBranchPresent && args[3] == "origin/main^{commit}" -> "basehead\n"
            args.first() == "log" && args.contains("--format=%H %P %ct") -> "head 1700000000\n"
            else -> throw GitCommandException("git ${args.first()} failed")
        }

        override fun fetch(args: List<String>, timeoutMillis: Long): FetchOutcome {
            fetches += args
            timeouts += timeoutMillis
            onFetch()
            return fetchOutcome(args)
        }

        fun deepens(): List<String> = fetches.mapNotNull { fetch -> fetch.firstOrNull { it.startsWith("--deepen=") } }
    }

    @Test
    fun `keeps the deepening steps within the history window`() {
        val runner = ScriptedGitRunner()

        val history = GitHistoryReader(runner, tempDir).read("head", "main", GitHistoryLimits(windowCommits = 120))

        assertEquals(listOf("--deepen=50", "--deepen=70"), runner.deepens())
        assertNull(history.mergeBaseSha)
        assertEquals("basehead", history.baseHeadSha)
        assertEquals("shallow clone: the merge base with main was not found within 60s", history.fallbackReason)
    }

    @Test
    fun `stops deepening after a failed fetch`() {
        val runner = ScriptedGitRunner(fetchOutcome = { FetchOutcome.FAILED })

        val history = GitHistoryReader(runner, tempDir).read("head", "main", GitHistoryLimits())

        assertEquals(listOf("--deepen=50"), runner.deepens())
        assertEquals("shallow clone: the merge base with main was not found within 60s", history.fallbackReason)
    }

    @Test
    fun `gives each fetch what is left of the budget and stops at the deadline`() {
        var now = 0L
        val runner = ScriptedGitRunner(onFetch = { now += 40_000 })

        GitHistoryReader(runner, tempDir, clock = { now }).read("head", "main", GitHistoryLimits(deepenBudgetSeconds = 60))

        assertEquals(listOf("--deepen=50", "--deepen=100"), runner.deepens())
        assertEquals(listOf(60_000L, 20_000L), runner.timeouts)
    }

    @Test
    fun `gives up on a base branch fetch still running at the deadline`() {
        val runner = ScriptedGitRunner(baseBranchPresent = false, fetchOutcome = { FetchOutcome.TIMED_OUT })

        val history = GitHistoryReader(runner, tempDir).read("head", "main", GitHistoryLimits(deepenBudgetSeconds = 5))

        assertEquals(1, runner.fetches.size)
        assertNull(history.baseHeadSha)
        assertEquals("the base branch main is not in the checkout and could not be fetched within 5s", history.fallbackReason)
        assertEquals(listOf("head"), history.commits.map { it.sha })
    }

    @Test
    fun `parseCommits reads the parents and committer time and skips malformed lines`() {
        val commits = GitHistoryParser.parseCommits("head mid side 1700000200\nroot  1700000000\nbad\n\n")

        assertEquals(
            listOf(
                GitHistoryCommit("head", listOf("mid", "side"), 1_700_000_200),
                GitHistoryCommit("root", emptyList(), 1_700_000_000)
            ),
            commits
        )
    }

    @Test
    fun `parseRawParents reads the parent headers and ignores indented lines`() {
        val output = """
            commit side
            tree t
            parent fork
            author A <a@tuist.dev> 1700000050 +0000
            committer A <a@tuist.dev> 1700000050 +0000
            gpgsig -----BEGIN PGP SIGNATURE-----
             parent signature
             -----END PGP SIGNATURE-----

                parent message

            commit boundary
            tree t
            parent outside
            parent other
            author A <a@tuist.dev> 1700000000 +0000
            committer A <a@tuist.dev> 1700000000 +0000

                merge
        """.trimIndent()

        assertEquals(
            mapOf("side" to listOf("fork"), "boundary" to listOf("outside", "other")),
            GitHistoryParser.parseRawParents(output)
        )
    }

    @Test
    fun `capture returns the output and throws when git fails`() {
        val repository = fixture.init(File(tempDir, "repository"))
        val plain = File(tempDir, "plain").apply { mkdirs() }

        assertEquals("true", ProcessGitRunner(repository, environment = fixture.environment).capture(listOf("rev-parse", "--is-inside-work-tree")).trim())
        assertThrows<GitCommandException> {
            ProcessGitRunner(plain, environment = fixture.environment).capture(listOf("rev-parse", "--is-inside-work-tree"))
        }
    }

    @Test
    fun `fetch reports how the command ended`() {
        assertEquals(FetchOutcome.SUCCEEDED, ProcessGitRunner(tempDir, gitExecutable = script("exit 0")).fetch(listOf("fetch"), 10_000))
        assertEquals(FetchOutcome.FAILED, ProcessGitRunner(tempDir, gitExecutable = script("exit 1")).fetch(listOf("fetch"), 10_000))
    }

    @Test
    fun `fetch kills a command still running at the timeout together with its child processes`() {
        val pidFile = File(tempDir, "child.pid")
        val runner = ProcessGitRunner(
            tempDir,
            gitExecutable = script("sleep 30 &\necho \$! > \"\$PID_FILE\"\nwait"),
            environment = mapOf("PID_FILE" to pidFile.absolutePath)
        )

        val started = System.nanoTime()
        val outcome = runner.fetch(listOf("fetch"), 1_000)
        val elapsedMillis = (System.nanoTime() - started) / 1_000_000

        assertEquals(FetchOutcome.TIMED_OUT, outcome)
        assertTrue(elapsedMillis < 10_000, "the fetch returned after ${elapsedMillis}ms")
        val child = ProcessHandle.of(pidFile.readText().trim().toLong())
        val deadline = System.currentTimeMillis() + 5_000
        while (child.map { it.isAlive }.orElse(false) && System.currentTimeMillis() < deadline) {
            Thread.sleep(50)
        }
        assertFalse(child.map { it.isAlive }.orElse(false), "the fetch's child process is still running")
    }

    private fun script(body: String): String {
        val file = File(tempDir, "git-${body.hashCode()}.sh")
        file.writeText("#!/bin/sh\n$body\n")
        file.setExecutable(true)
        return file.absolutePath
    }
}
