package dev.tuist.gradle

import java.io.File
import java.time.Duration
import java.time.Instant

/**
 * Builds real Git repositories for tests, isolated from the machine's Git configuration. Every
 * commit is a minute after the previous one, starting a day ago, so commit dates are distinct
 * and inside any history window.
 */
internal class GitRepositoryFixture {
    private val start = Instant.now().minus(Duration.ofDays(1)).epochSecond
    private var commits = 0

    val environment: Map<String, String> = mapOf(
        "GIT_CONFIG_GLOBAL" to "/dev/null",
        "GIT_CONFIG_NOSYSTEM" to "1",
        "GIT_AUTHOR_NAME" to "Tuist",
        "GIT_AUTHOR_EMAIL" to "tuist@tuist.dev",
        "GIT_COMMITTER_NAME" to "Tuist",
        "GIT_COMMITTER_EMAIL" to "tuist@tuist.dev"
    )

    fun git(directory: File, vararg args: String, extraEnvironment: Map<String, String> = emptyMap()): String {
        val process = ProcessBuilder(
            listOf("git", "-c", "init.defaultBranch=main", "-c", "commit.gpgsign=false") + args
        )
            .directory(directory)
            .redirectErrorStream(true)
            .apply { environment().putAll(this@GitRepositoryFixture.environment + extraEnvironment) }
            .start()
        val output = process.inputStream.bufferedReader().readText()
        check(process.waitFor() == 0) { "git ${args.joinToString(" ")} failed: $output" }
        return output.trim()
    }

    fun init(directory: File): File {
        directory.mkdirs()
        git(directory, "init", "-q")
        return directory
    }

    /** Commits a change and returns the commit's SHA. */
    fun commit(directory: File, message: String): String {
        commits += 1
        val date = "${start + commits * 60} +0000"
        File(directory, "history.txt").appendText("$message\n")
        git(directory, "add", "history.txt")
        git(
            directory, "commit", "-q", "-m", message,
            extraEnvironment = mapOf("GIT_AUTHOR_DATE" to date, "GIT_COMMITTER_DATE" to date)
        )
        return git(directory, "rev-parse", "HEAD")
    }

    /**
     * Merges [branch] into the current branch with a merge commit and returns the commit's SHA. The
     * merge keeps the current branch's tree, so the lines each commit appends never conflict.
     */
    fun merge(directory: File, branch: String, message: String): String {
        commits += 1
        val date = "${start + commits * 60} +0000"
        git(
            directory, "merge", "-q", "--no-ff", "-s", "ours", "-m", message, branch,
            extraEnvironment = mapOf("GIT_AUTHOR_DATE" to date, "GIT_COMMITTER_DATE" to date)
        )
        return git(directory, "rev-parse", "HEAD")
    }

    /**
     * Checks out [ref] of [url] the way `actions/checkout` checks out a pull request: that ref
     * alone, at depth 1, detached.
     */
    fun shallowCheckout(url: String, ref: String, directory: File): File {
        init(directory)
        git(directory, "remote", "add", "origin", url)
        git(directory, "fetch", "-q", "--no-tags", "--depth=1", "origin", "+$ref:refs/remotes/${ref.removePrefix("refs/")}")
        git(directory, "checkout", "-q", "--detach", "refs/remotes/${ref.removePrefix("refs/")}")
        return directory
    }

    /**
     * A bare origin with a pull request: `feature` forked from `main` at [forkPoint] and has
     * [pullRequestHead], `main` moved on to [mainHead], and `refs/pull/7/merge` is [merge], whose
     * parents are [mainHead] and [pullRequestHead]. The origin serves partial fetches, as GitHub does.
     */
    data class PullRequestOrigin(
        val url: String,
        val forkPoint: String,
        val pullRequestHead: String,
        val mainHead: String,
        val merge: String
    )

    fun pullRequestOrigin(directory: File): PullRequestOrigin {
        val seed = init(File(directory, "seed"))
        commit(seed, "A1")
        commit(seed, "A2")
        val forkPoint = commit(seed, "A3")
        git(seed, "checkout", "-q", "-b", "feature")
        commit(seed, "F1")
        val pullRequestHead = commit(seed, "F2")
        git(seed, "checkout", "-q", "main")
        commit(seed, "M1")
        val mainHead = commit(seed, "M2")
        git(seed, "checkout", "-q", "--detach", "main")
        val merge = merge(seed, "feature", "Merge feature into main")
        git(seed, "update-ref", "refs/pull/7/merge", merge)
        git(seed, "checkout", "-q", "main")
        val bare = File(directory, "origin.git")
        git(directory, "clone", "-q", "--bare", seed.absolutePath, bare.absolutePath)
        git(bare, "fetch", "-q", seed.absolutePath, "+refs/pull/7/merge:refs/pull/7/merge")
        git(bare, "config", "uploadpack.allowFilter", "true")
        return PullRequestOrigin("file://${bare.absolutePath}", forkPoint, pullRequestHead, mainHead, merge)
    }

    fun hasObject(directory: File, sha: String): Boolean =
        runCatching { git(directory, "cat-file", "-e", "$sha^{commit}") }.isSuccess

    fun committedAt(directory: File, sha: String): Long = git(directory, "show", "-s", "--format=%ct", sha).toLong()

    fun isShallow(directory: File): Boolean = git(directory, "rev-parse", "--is-shallow-repository") == "true"

    fun hasRef(directory: File, ref: String): Boolean =
        runCatching { git(directory, "rev-parse", "--verify", "--quiet", ref) }.isSuccess
}
