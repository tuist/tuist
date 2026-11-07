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
    /** How long asking the remote for the base branch's head may take. */
    val deepenBudgetSeconds: Int = 60,
    val remoteAccess: GitHistoryRemoteAccess = GitHistoryRemoteAccess.BASE_HEAD
)

/**
 * What collecting a run's history may read from the remote. Every remote call is a round trip of
 * most of a second whatever it transfers, so history is never fetched.
 */
enum class GitHistoryRemoteAccess {
    /** Only what the checkout has. */
    NONE,

    /** The base branch's latest commit (`git ls-remote`) when the checkout lacks the base branch. */
    BASE_HEAD
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

interface GitRunner {
    /** The standard output of `git <args>`; throws [GitCommandException] when it exits with a failure. */
    fun capture(args: List<String>): String

    /** The standard output of `git <args>`, or null when it fails or outlives the timeout. */
    fun captureWithin(args: List<String>, timeoutMillis: Long): String?
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
            // A stalled remote keeps `git-remote-https` or `ssh` alive after `git` itself is gone.
            val descendants = process.descendants().toList()
            process.destroyForcibly()
            descendants.forEach { it.destroyForcibly() }
            return null
        } finally {
            output.delete()
        }
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
 * Reads a run's history from the checkout: the merge base with the base branch, the base branch's
 * head, and the commits reachable from the head and the checkout's base head within the window.
 * When the checkout lacks the base branch, its head is asked from the remote with one bounded
 * `git ls-remote`, which transfers no objects. History is never fetched.
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
            val ref = baseRef(baseBranch)
            if (ref == null) {
                reason = "the base branch $baseBranch is not in the checkout"
                if (limits.remoteAccess == GitHistoryRemoteAccess.BASE_HEAD) {
                    baseHeadSha = remoteBranchHead(baseBranch, limits.deepenBudgetSeconds)
                }
            } else {
                localBaseHeadSha = commitSha(ref)
                baseHeadSha = localBaseHeadSha
                mergeBaseSha = mergeBase(ref, headSha)
                reason = when {
                    mergeBaseSha != null -> null
                    isShallow() -> "shallow clone: the merge base with $baseBranch is not in the checkout"
                    else -> "${headSha.take(12)} and $baseBranch share no history in the checkout"
                }
            }
        }

        // On a pull request's merge checkout the head is the merge commit's second parent, which a
        // depth-1 checkout does not contain.
        val headInCheckout = commitSha(headSha) != null
        val heads = listOfNotNull(headSha.takeIf { headInCheckout }) + listOfNotNull(localBaseHeadSha).filter { it != headSha }
        return GitHistory(
            objectFormat = objectFormat,
            headSha = headSha,
            baseBranch = baseBranch,
            mergeBaseSha = mergeBaseSha,
            baseHeadSha = baseHeadSha,
            commits = if (heads.isEmpty()) emptyList() else windowCommits(heads, limits),
            fallbackReason = listOfNotNull(reason, "${headSha.take(12)} is not in the checkout".takeUnless { headInCheckout })
                .joinToString("; ")
                .ifEmpty { null }
        )
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
}
