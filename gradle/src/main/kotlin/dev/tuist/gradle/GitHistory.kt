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
    val deepenBudgetSeconds: Int = 60,
    /** Whether the base branch may be fetched and a shallow clone deepened. */
    val unshallow: Boolean = true
)

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
    /** The base branch's commit as the checkout saw it. */
    val baseHeadSha: String?,
    /** The commits reachable from the head, and from the base branch's commit, within the limits, newest first. */
    val commits: List<GitHistoryCommit>,
    val fallbackReason: String?
)

class GitCommandException(message: String) : Exception(message)

enum class FetchOutcome { SUCCEEDED, FAILED, TIMED_OUT }

interface GitRunner {
    /** The standard output of `git <args>`; throws [GitCommandException] when it exits with a failure. */
    fun capture(args: List<String>): String

    /** Runs `git <args>` until it exits or the timeout passes, whichever comes first. */
    fun fetch(args: List<String>, timeoutMillis: Long): FetchOutcome
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

    override fun fetch(args: List<String>, timeoutMillis: Long): FetchOutcome {
        if (timeoutMillis <= 0) return FetchOutcome.TIMED_OUT
        val process = processBuilder(args)
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()
        if (process.waitFor(timeoutMillis, TimeUnit.MILLISECONDS)) {
            return if (process.exitValue() == 0) FetchOutcome.SUCCEEDED else FetchOutcome.FAILED
        }
        // A stalled remote keeps `git-remote-https`, `ssh` or `index-pack` alive after `git` itself is gone.
        val descendants = process.descendants().toList()
        process.destroyForcibly()
        descendants.forEach { it.destroyForcibly() }
        return FetchOutcome.TIMED_OUT
    }

    private fun processBuilder(args: List<String>): ProcessBuilder =
        ProcessBuilder(listOf(gitExecutable) + args)
            .directory(workingDirectory)
            .apply { environment().putAll(nonInteractiveEnvironment + environment) }

    companion object {
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
}

/**
 * Reads a run's history from the checkout: the merge base with the base branch, fetching the base
 * branch and deepening a shallow clone within the time budget when allowed, the base branch's head,
 * and the commits reachable from both heads within the window.
 */
class GitHistoryReader(
    private val git: GitRunner,
    private val workingDirectory: File,
    private val clock: () -> Long = System::currentTimeMillis
) : GitHistoryReading {

    override fun isRepository(): Boolean =
        runCatching { git.capture(listOf("rev-parse", "--is-inside-work-tree")).trim() == "true" }.getOrDefault(false)

    override fun read(headSha: String, baseBranch: String?, limits: GitHistoryLimits): GitHistory {
        val objectFormat = runCatching { git.capture(listOf("rev-parse", "--show-object-format")).trim() }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }
            ?: "sha1"

        var resolution = MergeBaseResolution(sha = null, ref = null, reason = "no base branch is known")
        var baseHeadSha: String? = null
        if (baseBranch != null) {
            resolution = resolveMergeBase(headSha, baseBranch, limits)
            // Read after any deepening, which fetches the base branch again and can move it.
            baseHeadSha = resolution.ref?.let(::commitSha)
        }

        val heads = listOf(headSha) + listOfNotNull(baseHeadSha).filter { it != headSha }
        return GitHistory(
            objectFormat = objectFormat,
            headSha = headSha,
            baseBranch = baseBranch,
            mergeBaseSha = resolution.sha,
            baseHeadSha = baseHeadSha,
            commits = windowCommits(heads, limits),
            fallbackReason = resolution.reason
        )
    }

    private data class MergeBaseResolution(val sha: String?, val ref: String?, val reason: String?)

    private fun commitSha(ref: String): String? =
        runCatching { git.capture(listOf("rev-parse", "--verify", "--quiet", "$ref^{commit}")).trim() }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }

    private fun mergeBase(ref: String, head: String): String? =
        runCatching { git.capture(listOf("merge-base", ref, head)).trim() }.getOrNull()?.takeIf { it.isNotEmpty() }

    private fun baseRef(baseBranch: String): String? =
        listOf("origin/$baseBranch", baseBranch).firstOrNull { commitSha(it) != null }

    private fun resolveMergeBase(head: String, baseBranch: String, limits: GitHistoryLimits): MergeBaseResolution {
        val deadline = clock() + limits.deepenBudgetSeconds * 1000L
        val shallow = runCatching { git.capture(listOf("rev-parse", "--is-shallow-repository")).trim() == "true" }
            .getOrDefault(false)

        // Only commits and trees place the merge base, and blobs are most of what a fetch carries.
        // `--filter=tree:0` would leave the trees out too, but Git 2.50 aborts deepening with it.
        val baseRefspec = "+$baseBranch:refs/remotes/origin/$baseBranch"
        var ref = baseRef(baseBranch)
        if (ref == null && !limits.unshallow) {
            return MergeBaseResolution(null, null, "the base branch $baseBranch is not in the checkout and fetching it is disabled")
        }
        if (ref == null) {
            val fetch = listOf("fetch", "--no-tags", "--filter=blob:none") +
                (if (shallow) listOf("--depth=1") else emptyList()) +
                listOf("origin", baseRefspec)
            if (git.fetch(fetch, deadline - clock()) == FetchOutcome.TIMED_OUT) {
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
        if (!shallow) {
            return MergeBaseResolution(null, ref, "${head.take(12)} and $baseBranch share no history in the checkout")
        }
        if (!limits.unshallow) {
            return MergeBaseResolution(
                null,
                ref,
                "shallow clone: the merge base with $baseBranch is not in the checkout and deepening it is disabled"
            )
        }

        // The base branch is named on every deepen: without a refspec, git fetches what the
        // checkout's config says, which on CI is often every branch with all of its history.
        // Deepening is relative to the current boundary, so the steps add up, and together they
        // stay within the history window. A failed fetch is not retried: one that fails at once,
        // offline or against a remote that refuses it, would otherwise be repeated until the budget ran out.
        val maxDepth = maxOf(limits.windowCommits, 50)
        var depth = 0
        var step = 50
        while (clock() < deadline && depth < maxDepth) {
            step = minOf(step, maxDepth - depth)
            val deepen = listOf("fetch", "--no-tags", "--filter=blob:none", "--deepen=$step", "origin", baseRefspec)
            if (git.fetch(deepen, deadline - clock()) != FetchOutcome.SUCCEEDED) break
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
}
