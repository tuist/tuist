package dev.tuist.gradle

import java.io.File
import java.util.concurrent.TimeUnit

/** A commit as the server's commit graph stores it: its parents, first parent first, and the committer time in epoch seconds. */
data class GitHistoryCommit(
    val sha: String,
    val parents: List<String>,
    val committedAt: Long
)

/** How much history is collected for a run. The server sets these; the defaults apply when it cannot be asked. */
data class GitHistoryLimits(
    val windowDays: Int = 365,
    val windowCommits: Int = 5000,
    /**
     * How long each remote step may take: asking for the base branch's head, fetching the base
     * branch and deepening to the merge base, and deepening to the commits the server has.
     */
    val deepenBudgetSeconds: Int = 60,
    val remoteAccess: GitHistoryRemoteAccess = GitHistoryRemoteAccess.BASE_HEAD
)

/**
 * What collecting a run's history may read from the remote. Every remote call is a round trip of
 * most of a second whatever it transfers, so only coverage, which needs the merge base, fetches.
 */
enum class GitHistoryRemoteAccess {
    /** Only what the checkout has. */
    NONE,

    /** The base branch's latest commit (`git ls-remote`) when the checkout lacks the base branch. */
    BASE_HEAD,

    /**
     * The base branch, and a shallow clone deepened until the merge base is found and until the
     * server has the commits the clone stops at.
     */
    HISTORY
}

/**
 * What a checkout tells about a run's place in the repository's history. Whatever could not be
 * resolved is null, with [fallbackReason] saying why.
 */
data class GitHistory(
    /** `sha1` or `sha256`. */
    val objectFormat: String,
    val headSha: String,
    val baseBranch: String?,
    val mergeBaseSha: String?,
    /** The base branch's commit as the checkout or the remote had it. */
    val baseHeadSha: String?,
    /**
     * The commits reachable from the head, and from the base branch's commit when the checkout has
     * it, within the limits, newest first.
     */
    val commits: List<GitHistoryCommit>,
    val fallbackReason: String?
)

class GitCommandException(message: String) : Exception(message)

enum class GitFetchOutcome { SUCCEEDED, FAILED, TIMED_OUT }

interface GitRunner {
    /** The standard output of `git <args>`; throws [GitCommandException] when it exits with a failure. */
    fun capture(args: List<String>): String

    /** The standard output of `git <args>`, or null when it fails or outlives the timeout. */
    fun captureWithin(args: List<String>, timeoutMillis: Long): String?

    /** Runs `git <args>`, a fetch, until it exits or the timeout passes, and says which came first. */
    fun fetchWithin(args: List<String>, timeoutMillis: Long): GitFetchOutcome
}

/**
 * Runs `git` in [workingDirectory], non-interactively: a credential prompt or a `gpg` signature
 * check would otherwise wait on input that never comes.
 */
class ProcessGitRunner(
    private val workingDirectory: File,
    private val gitExecutable: String = "git",
    private val environment: Map<String, String> = emptyMap()
) : GitRunner {
    override fun capture(args: List<String>): String {
        val process = processBuilder(args).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        val exitCode = process.waitFor()
        if (exitCode != 0) throw GitCommandException("git ${args.first()} failed (exit code $exitCode)")
        return output
    }

    override fun captureWithin(args: List<String>, timeoutMillis: Long): String? {
        if (timeoutMillis <= 0) return null
        val output = File.createTempFile("tuist-git", ".out")
        try {
            val process = processBuilder(args)
                .redirectOutput(output)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start()
            if (process.waitFor(timeoutMillis, TimeUnit.MILLISECONDS)) {
                return if (process.exitValue() == 0) output.readText() else null
            }
            stop(process)
            return null
        } finally {
            output.delete()
        }
    }

    override fun fetchWithin(args: List<String>, timeoutMillis: Long): GitFetchOutcome {
        if (timeoutMillis <= 0) return GitFetchOutcome.TIMED_OUT
        val process = processBuilder(args)
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()
        if (process.waitFor(timeoutMillis, TimeUnit.MILLISECONDS)) {
            return if (process.exitValue() == 0) GitFetchOutcome.SUCCEEDED else GitFetchOutcome.FAILED
        }
        stop(process)
        return GitFetchOutcome.TIMED_OUT
    }

    /**
     * Stops a command still running at its deadline together with the processes it started: a
     * stalled remote keeps `git-remote-https`, `ssh` or `index-pack` alive after `git` itself is
     * gone. SIGTERM first, on which git removes its lock files (a deepening killed outright leaves
     * `shallow.lock` behind, which fails every later fetch of the checkout), and SIGKILL for
     * whatever is still running a second later.
     */
    private fun stop(process: Process) {
        val descendants = process.descendants().toList()
        process.destroy()
        descendants.forEach { it.destroy() }
        if (!process.waitFor(STOP_GRACE_MILLIS, TimeUnit.MILLISECONDS)) process.destroyForcibly()
        descendants.filter { it.isAlive }.forEach { it.destroyForcibly() }
    }

    private fun processBuilder(args: List<String>): ProcessBuilder =
        ProcessBuilder(listOf(gitExecutable) + args)
            .directory(workingDirectory)
            .apply { environment().putAll(nonInteractiveEnvironment + environment) }

    companion object {
        private const val STOP_GRACE_MILLIS = 1_000L

        private val nonInteractiveEnvironment = mapOf(
            "GIT_TERMINAL_PROMPT" to "0",
            "GIT_ASKPASS" to "/usr/bin/false",
            "GIT_CONFIG_COUNT" to "1",
            "GIT_CONFIG_KEY_0" to "log.showSignature",
            "GIT_CONFIG_VALUE_0" to "false"
        )
    }
}

internal object GitHistoryParser {
    /** `git log --format=%H %P %ct` lines: the SHA, the parent SHAs and the committer time. */
    fun parseCommits(output: String): List<GitHistoryCommit> =
        output.lineSequence().mapNotNull { line ->
            val fields = line.split(' ').filter { it.isNotEmpty() }
            val time = fields.lastOrNull()?.toLongOrNull()
            if (fields.size < 2 || time == null) return@mapNotNull null
            GitHistoryCommit(sha = fields.first(), parents = fields.subList(1, fields.size - 1), committedAt = time)
        }.toList()

    /**
     * The parents of each commit in a `git log --format=raw` listing, as the commit objects store
     * them. Headers start at the line's first column; the message and multi-line header values are indented.
     */
    fun parseRawParents(output: String): Map<String, List<String>> {
        val parents = linkedMapOf<String, MutableList<String>>()
        var current: String? = null
        for (line in output.lineSequence()) {
            when {
                line.startsWith("commit ") -> {
                    val sha = line.removePrefix("commit ").substringBefore(' ')
                    current = sha
                    parents[sha] = mutableListOf()
                }
                line.startsWith("parent ") -> current?.let { parents.getValue(it).add(line.removePrefix("parent ").trim()) }
            }
        }
        return parents
    }
}

interface GitHistoryReading {
    fun isRepository(): Boolean

    fun read(headSha: String, baseBranch: String?, limits: GitHistoryLimits): GitHistory

    /**
     * The history with the gap a shallow clone leaves below it closed, deepening through [branch]
     * while [unknown] says the server lacks a commit the clone stops at. Only with
     * [GitHistoryRemoteAccess.HISTORY]; otherwise the history as it is.
     */
    fun connect(history: GitHistory, branch: String, limits: GitHistoryLimits, unknown: (List<String>) -> List<String>): GitHistory
}

/**
 * Reads a run's history from the checkout: the merge base with the base branch, the base branch's
 * head, and the commits reachable from the head and the checkout's base head within the window.
 * What reaches the remote is [GitHistoryLimits.remoteAccess]: with [GitHistoryRemoteAccess.BASE_HEAD]
 * a checkout without the base branch has its head asked with one bounded `git ls-remote`, which
 * transfers no objects; with [GitHistoryRemoteAccess.HISTORY] the base branch is fetched and a
 * shallow clone deepened within the budget, as the CLI does on coverage runs
 * (`GitController+History.swift`).
 */
class GitHistoryReader(
    private val git: GitRunner,
    private val workingDirectory: File
) : GitHistoryReading {

    override fun isRepository(): Boolean =
        runCatching { git.capture(listOf("rev-parse", "--is-inside-work-tree")).trim() == "true" }.getOrDefault(false)

    override fun read(headSha: String, baseBranch: String?, limits: GitHistoryLimits): GitHistory {
        val objectFormat = runCatching { git.capture(listOf("rev-parse", "--show-object-format")).trim() }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }
            ?: "sha1"

        var mergeBaseSha: String? = null
        var baseHeadSha: String? = null
        var localBaseHeadSha: String? = null
        val reason: String?
        if (baseBranch == null) {
            reason = "no base branch is known"
        } else {
            val resolved = resolveMergeBase(headSha, baseBranch, limits)
            mergeBaseSha = resolved.sha
            reason = resolved.reason
            // Read after any deepening, which fetches the base branch again and can move it.
            if (resolved.ref != null) {
                localBaseHeadSha = commitSha(resolved.ref)
                baseHeadSha = localBaseHeadSha
            } else if (limits.remoteAccess == GitHistoryRemoteAccess.BASE_HEAD) {
                baseHeadSha = remoteBranchHead(baseBranch, limits.deepenBudgetSeconds)
            }
        }

        val heads = listOf(headSha) + listOfNotNull(localBaseHeadSha).filter { it != headSha }
        return GitHistory(
            objectFormat = objectFormat,
            headSha = headSha,
            baseBranch = baseBranch,
            mergeBaseSha = mergeBaseSha,
            baseHeadSha = baseHeadSha,
            commits = windowCommits(heads, limits),
            fallbackReason = reason
        )
    }

    /**
     * The server places a commit on its branch from the parents it has when the commit arrives,
     * so a depth-1 push whose parent no run has uploaded yet would leave that parent off the
     * branch for good. While the server lacks a first parent the clone stops at, the clone is
     * deepened through [branch] with the merge base's steps and bounds, and its commits listed
     * again. A parent a fetch leaves out of reach (the remote's branch was rewritten) is dropped
     * rather than fetched for again.
     */
    override fun connect(
        history: GitHistory,
        branch: String,
        limits: GitHistoryLimits,
        unknown: (List<String>) -> List<String>
    ): GitHistory {
        if (limits.remoteAccess != GitHistoryRemoteAccess.HISTORY) return history
        val heads = listOf(history.headSha) + listOfNotNull(history.baseHeadSha).filter { it != history.headSha }
        var commits = history.commits
        var parents = boundaryFirstParents(commits, heads)
        val unreachable = mutableSetOf<String>()

        val deadline = Deadline(limits.deepenBudgetSeconds)
        val maxDepth = maxOf(limits.windowCommits, INITIAL_DEEPEN_STEP)
        var depth = 0
        var step = INITIAL_DEEPEN_STEP
        while (parents.isNotEmpty() && !deadline.passed() && depth < maxDepth && unknown(parents).isNotEmpty()) {
            step = minOf(step, maxDepth - depth)
            // Deepening is relative to every commit the clone stops at, so naming one branch the
            // remote has also deepens a head that is not on it, a pull request's merge commit. The
            // full ref is never read as a tag or an option, and the empty refmap keeps the
            // checkout's own `origin/<branch>` where the job's later steps expect it.
            val deepen = listOf(
                "fetch", "--no-tags", "--refmap=", "--filter=blob:none", "--deepen=$step", "origin", "refs/heads/$branch"
            )
            if (git.fetchWithin(deepen, deadline.remainingMillis()) != GitFetchOutcome.SUCCEEDED) break
            commits = runCatching { windowCommits(heads, limits) }.getOrNull() ?: break
            val reached = boundaryFirstParents(commits, heads)
            unreachable += reached.filter { it in parents }
            parents = reached.filter { it !in unreachable }
            depth += step
            step *= 2
        }
        return history.copy(commits = commits)
    }

    /**
     * The first parents the checkout lacks: where each head's first-parent chain reaches a commit
     * the shallow clone stops at. A chain that ends at a root, or at the history window, has none.
     */
    private fun boundaryFirstParents(commits: List<GitHistoryCommit>, heads: List<String>): List<String> {
        val boundary = shallowBoundary() ?: return emptyList()
        if (boundary.isEmpty()) return emptyList()
        val bySha = HashMap<String, GitHistoryCommit>()
        commits.forEach { bySha.putIfAbsent(it.sha, it) }
        val parents = mutableListOf<String>()
        for (head in heads) {
            var commit = bySha[head]
            val walked = mutableSetOf<String>()
            while (commit != null && walked.add(commit.sha)) {
                val parent = commit.parents.firstOrNull() ?: break
                val next = bySha[parent]
                if (next == null && commit.sha in boundary && parent !in parents) parents += parent
                commit = next
            }
        }
        return parents
    }

    /**
     * The merge base between the head and the base branch. With [GitHistoryRemoteAccess.HISTORY],
     * the base branch is fetched when the checkout lacks it and a shallow clone deepened in growing
     * steps until the merge base is found or the budget runs out. Every fetch names the base
     * branch: without a refspec git fetches what the checkout's config says, which for
     * `actions/checkout` is every branch with however much history each has. Only commits and
     * trees place the merge base, and blobs are most of what a fetch carries, hence
     * `--filter=blob:none` (`--filter=tree:0` makes Git 2.50 abort deepening); a server without
     * filters ignores it and sends everything.
     */
    private fun resolveMergeBase(head: String, baseBranch: String, limits: GitHistoryLimits): MergeBaseResolution {
        val deadline = Deadline(limits.deepenBudgetSeconds)
        val shallow = isShallow()
        val refspec = "+$baseBranch:refs/remotes/origin/$baseBranch"

        var ref = baseRef(baseBranch)
        if (ref == null && limits.remoteAccess != GitHistoryRemoteAccess.HISTORY) {
            return MergeBaseResolution(null, null, "the base branch $baseBranch is not in the checkout")
        }
        if (ref == null) {
            val fetch = listOf("fetch", "--no-tags", "--filter=blob:none") +
                (if (shallow) listOf("--depth=1") else emptyList()) +
                listOf("origin", refspec)
            if (git.fetchWithin(fetch, deadline.remainingMillis()) == GitFetchOutcome.TIMED_OUT) {
                return MergeBaseResolution(
                    null,
                    null,
                    "the base branch $baseBranch is not in the checkout and could not be fetched within ${limits.deepenBudgetSeconds}s"
                )
            }
            ref = baseRef(baseBranch)
                ?: return MergeBaseResolution(null, null, "the base branch $baseBranch is not in the checkout and could not be fetched")
        }

        mergeBase(ref, head)?.let { return MergeBaseResolution(it, ref, null) }
        if (!shallow) return MergeBaseResolution(null, ref, "${head.take(12)} and $baseBranch share no history in the checkout")
        if (limits.remoteAccess != GitHistoryRemoteAccess.HISTORY) {
            return MergeBaseResolution(null, ref, "shallow clone: the merge base with $baseBranch is not in the checkout")
        }

        // Deepening is relative to the current boundary, so the steps add up, and together they stay
        // within the history window. Never past a fetch that failed either: one that fails at once,
        // offline or against a remote that refuses it, would otherwise be retried until the budget ran out.
        val maxDepth = maxOf(limits.windowCommits, INITIAL_DEEPEN_STEP)
        var depth = 0
        var step = INITIAL_DEEPEN_STEP
        while (!deadline.passed() && depth < maxDepth) {
            step = minOf(step, maxDepth - depth)
            val deepen = listOf("fetch", "--no-tags", "--filter=blob:none", "--deepen=$step", "origin", refspec)
            if (git.fetchWithin(deepen, deadline.remainingMillis()) != GitFetchOutcome.SUCCEEDED) break
            mergeBase(ref, head)?.let { return MergeBaseResolution(it, ref, null) }
            depth += step
            step *= 2
        }
        return MergeBaseResolution(
            null,
            ref,
            "shallow clone: the merge base with $baseBranch was not found within ${limits.deepenBudgetSeconds}s"
        )
    }

    /** The merge base, the base branch's ref it was resolved against, and why either is missing. */
    private data class MergeBaseResolution(val sha: String?, val ref: String?, val reason: String?)

    /** One budget shared by the remote steps it bounds. */
    private class Deadline(budgetSeconds: Int) {
        private val endNanos = System.nanoTime() + TimeUnit.SECONDS.toNanos(budgetSeconds.toLong())

        fun remainingMillis(): Long = TimeUnit.NANOSECONDS.toMillis(endNanos - System.nanoTime())

        fun passed(): Boolean = endNanos - System.nanoTime() <= 0
    }

    private fun commitSha(ref: String): String? =
        runCatching { git.capture(listOf("rev-parse", "--verify", "--quiet", "$ref^{commit}")).trim() }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }

    private fun mergeBase(ref: String, head: String): String? =
        runCatching { git.capture(listOf("merge-base", ref, head)).trim() }.getOrNull()?.takeIf { it.isNotEmpty() }

    private fun baseRef(baseBranch: String): String? =
        listOf("origin/$baseBranch", baseBranch).firstOrNull { commitSha(it) != null }

    private fun isShallow(): Boolean =
        runCatching { git.capture(listOf("rev-parse", "--is-shallow-repository")).trim() == "true" }.getOrDefault(false)

    private fun remoteBranchHead(branch: String, budgetSeconds: Int): String? =
        git.captureWithin(listOf("ls-remote", "origin", "refs/heads/$branch"), budgetSeconds * 1000L)
            ?.trim()
            ?.split(Regex("\\s+"))
            ?.firstOrNull()
            ?.takeIf { it.isNotEmpty() }

    /**
     * The commits reachable from the heads within the window. `git log` lists a shallow clone's
     * boundary commits without parents, so theirs are read from the commit objects. When they
     * cannot be read, the boundary commits are left out rather than stored as roots.
     */
    private fun windowCommits(heads: List<String>, limits: GitHistoryLimits): List<GitHistoryCommit> {
        val commits = GitHistoryParser.parseCommits(
            git.capture(
                listOf("log", "--format=%H %P %ct", "--max-count=${limits.windowCommits}", "--since=${limits.windowDays}.days.ago") + heads
            )
        )
        val boundary = shallowBoundary() ?: return commits
        val windowBoundary = commits.map { it.sha }.filter { it in boundary }
        if (windowBoundary.isEmpty()) return commits

        val parents = runCatching {
            GitHistoryParser.parseRawParents(git.capture(listOf("log", "--no-walk", "--no-decorate", "--format=raw") + windowBoundary))
        }.getOrDefault(emptyMap())
        return commits.mapNotNull { commit ->
            if (commit.sha !in boundary) commit else parents[commit.sha]?.let { commit.copy(parents = it) }
        }
    }

    private fun shallowBoundary(): Set<String>? {
        val path = runCatching { git.capture(listOf("rev-parse", "--git-path", "shallow")).trim() }.getOrNull() ?: return null
        val file = File(path).let { if (it.isAbsolute) it else File(workingDirectory, path) }
        if (!file.isFile) return null
        return runCatching { file.readLines().map { it.trim() }.filter { it.isNotEmpty() }.toSet() }.getOrNull()
    }

    private companion object {
        /** The first deepening step, which doubles at every step after it. */
        const val INITIAL_DEEPEN_STEP = 50
    }
}
