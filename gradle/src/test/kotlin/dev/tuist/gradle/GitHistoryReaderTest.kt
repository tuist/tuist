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

    /** Records every command that reaches past the checkout. */
    private class RecordingGitRunner(private val delegate: GitRunner) : GitRunner {
        val remoteCommands = mutableListOf<List<String>>()

        override fun capture(args: List<String>): String {
            if (args.first() in remoteCommandNames) remoteCommands += args
            return delegate.capture(args)
        }

        override fun captureWithin(args: List<String>, timeoutMillis: Long): String? {
            remoteCommands += args
            return delegate.captureWithin(args, timeoutMillis)
        }

        private val remoteCommandNames = setOf("fetch", "ls-remote", "pull", "remote")
    }

    private fun reader(checkout: File): Pair<GitHistoryReader, RecordingGitRunner> {
        val runner = RecordingGitRunner(ProcessGitRunner(checkout, environment = fixture.environment))
        return GitHistoryReader(runner, checkout) to runner
    }

    @Test
    fun `finds the merge base of a full clone without contacting the remote`() {
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
        assertTrue(runner.remoteCommands.isEmpty())
        assertEquals(7, history.commits.size)
        assertEquals(origin.mainHead, history.commits.first().sha)
        val bySha = history.commits.associateBy { it.sha }
        assertEquals(listOf(origin.forkPoint), bySha.getValue(origin.feature).parents)
        assertEquals(emptyList(), bySha.getValue(origin.firstCommit).parents)
        assertEquals(fixture.committedAt(checkout, origin.feature), bySha.getValue(origin.feature).committedAt)
    }

    @Test
    fun `asks the remote for the base branch head when the checkout lacks the base branch`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--branch", "feature")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.feature, "main", GitHistoryLimits())

        assertNull(history.mergeBaseSha)
        assertEquals(origin.mainHead, history.baseHeadSha)
        assertEquals("the base branch main is not in the checkout", history.fallbackReason)
        assertEquals(listOf(listOf("ls-remote", "origin", "refs/heads/main")), runner.remoteCommands)
        assertFalse(fixture.hasRef(checkout, "refs/remotes/origin/main"))
        assertTrue(fixture.isShallow(checkout))
        assertEquals(
            listOf(GitHistoryCommit(origin.feature, listOf(origin.forkPoint), fixture.committedAt(checkout, origin.feature))),
            history.commits
        )
    }

    @Test
    fun `never contacts the remote when remote access is disabled`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--branch", "feature")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.feature, "main", GitHistoryLimits(remoteAccess = GitHistoryRemoteAccess.NONE))

        assertNull(history.mergeBaseSha)
        assertNull(history.baseHeadSha)
        assertEquals("the base branch main is not in the checkout", history.fallbackReason)
        assertTrue(runner.remoteCommands.isEmpty())
        assertEquals(listOf(origin.feature), history.commits.map { it.sha })
    }

    @Test
    fun `reads the shallow base branch the checkout has without deepening`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--no-single-branch", "--branch", "feature")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.feature, "main", GitHistoryLimits())

        assertNull(history.mergeBaseSha)
        assertEquals(origin.mainHead, history.baseHeadSha)
        assertEquals("shallow clone: the merge base with main is not in the checkout", history.fallbackReason)
        assertTrue(runner.remoteCommands.isEmpty())
        val bySha = history.commits.associateBy { it.sha }
        assertEquals(setOf(origin.feature, origin.mainHead), bySha.keys)
        assertEquals(listOf(origin.forkPoint), bySha.getValue(origin.feature).parents)
        assertEquals(listOf(origin.mainParent), bySha.getValue(origin.mainHead).parents)
    }

    @Test
    fun `restores the parents of a shallow clone's boundary commits`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--branch", "main")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.mainHead, null, GitHistoryLimits())

        assertTrue(fixture.isShallow(checkout))
        assertEquals(
            listOf(GitHistoryCommit(origin.mainHead, listOf(origin.mainParent), fixture.committedAt(checkout, origin.mainHead))),
            history.commits
        )
        assertEquals("no base branch is known", history.fallbackReason)
        assertTrue(runner.remoteCommands.isEmpty())
    }

    @Test
    fun `reports a base branch neither the checkout nor the remote has`() {
        val origin = origin()
        val checkout = clone(origin, "--depth=1", "--branch", "feature")
        val (reader, _) = reader(checkout)

        val history = reader.read(origin.feature, "release", GitHistoryLimits())

        assertNull(history.mergeBaseSha)
        assertNull(history.baseHeadSha)
        assertEquals("the base branch release is not in the checkout", history.fallbackReason)
        assertEquals(listOf(origin.feature), history.commits.map { it.sha })
    }

    @Test
    fun `leaves out a head a depth-one pull request merge checkout does not have`() {
        // `actions/checkout`'s default: `refs/pull/N/merge` at depth 1, with the merge commit, not the
        // pull request's head the run reports.
        val origin = origin()
        val checkout = fixture.init(File(tempDir, "checkout"))
        fixture.git(checkout, "remote", "add", "origin", origin.url)
        fixture.git(checkout, "fetch", "-q", "--depth=1", "origin", "+main:refs/remotes/origin/main")
        val (reader, runner) = reader(checkout)

        val history = reader.read(origin.feature, "main", GitHistoryLimits())

        assertEquals(origin.feature, history.headSha)
        assertNull(history.mergeBaseSha)
        assertEquals(origin.mainHead, history.baseHeadSha)
        assertEquals(
            "shallow clone: the merge base with main is not in the checkout; ${origin.feature.take(12)} is not in the checkout",
            history.fallbackReason
        )
        assertEquals(listOf(origin.mainHead), history.commits.map { it.sha })
        assertTrue(runner.remoteCommands.isEmpty())
    }

    @Test
    fun `isRepository tells a checkout from a plain directory`() {
        val repository = fixture.init(File(tempDir, "repository"))
        val plain = File(tempDir, "plain").apply { mkdirs() }

        assertTrue(GitHistoryReader(ProcessGitRunner(repository, environment = fixture.environment), repository).isRepository())
        assertFalse(GitHistoryReader(ProcessGitRunner(plain, environment = fixture.environment), plain).isRepository())
    }

    /** A checkout without the base branch whose remote never answers in time. */
    private class StalledRemoteGitRunner : GitRunner {
        val timeouts = mutableListOf<Long>()

        override fun capture(args: List<String>): String = when {
            args == listOf("rev-parse", "--show-object-format") -> "sha1\n"
            args == listOf("rev-parse", "--verify", "--quiet", "head^{commit}") -> "head\n"
            args.first() == "log" && args.contains("--format=%H %P %ct") -> "head 1700000000\n"
            else -> throw GitCommandException("git ${args.first()} failed")
        }

        override fun captureWithin(args: List<String>, timeoutMillis: Long): String? {
            timeouts += timeoutMillis
            return null
        }
    }

    @Test
    fun `bounds the remote lookup by the budget`() {
        val runner = StalledRemoteGitRunner()

        val history = GitHistoryReader(runner, tempDir).read("head", "main", GitHistoryLimits(deepenBudgetSeconds = 5))

        assertEquals(listOf(5_000L), runner.timeouts)
        assertNull(history.baseHeadSha)
        assertEquals("the base branch main is not in the checkout", history.fallbackReason)
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
    fun `captureWithin returns the output of a command that succeeds in time`() {
        assertEquals("abc\trefs/heads/main", ProcessGitRunner(tempDir, gitExecutable = script("printf 'abc\\trefs/heads/main\\n'")).captureWithin(listOf("ls-remote"), 10_000)?.trim())
        assertNull(ProcessGitRunner(tempDir, gitExecutable = script("echo out; exit 1")).captureWithin(listOf("ls-remote"), 10_000))
    }

    @Test
    fun `captureWithin kills a command still running at the timeout together with its child processes`() {
        val pidFile = File(tempDir, "child.pid")
        val runner = ProcessGitRunner(
            tempDir,
            gitExecutable = script("sleep 30 &\necho \$! > \"\$PID_FILE\"\nwait"),
            environment = mapOf("PID_FILE" to pidFile.absolutePath)
        )

        val started = System.nanoTime()
        val output = runner.captureWithin(listOf("ls-remote"), 1_000)
        val elapsedMillis = (System.nanoTime() - started) / 1_000_000

        assertNull(output)
        assertTrue(elapsedMillis < 10_000, "the command returned after ${elapsedMillis}ms")
        val child = ProcessHandle.of(pidFile.readText().trim().toLong())
        val deadline = System.currentTimeMillis() + 5_000
        while (child.map { it.isAlive }.orElse(false) && System.currentTimeMillis() < deadline) {
            Thread.sleep(50)
        }
        assertFalse(child.map { it.isAlive }.orElse(false), "the command's child process is still running")
    }

    private fun script(body: String): String {
        val file = File(tempDir, "git-${body.hashCode()}.sh")
        file.writeText("#!/bin/sh\n$body\n")
        file.setExecutable(true)
        return file.absolutePath
    }
}
