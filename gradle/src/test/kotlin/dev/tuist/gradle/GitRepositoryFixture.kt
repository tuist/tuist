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

    fun committedAt(directory: File, sha: String): Long = git(directory, "show", "-s", "--format=%ct", sha).toLong()

    fun isShallow(directory: File): Boolean = git(directory, "rev-parse", "--is-shallow-repository") == "true"

    fun hasRef(directory: File, ref: String): Boolean =
        runCatching { git(directory, "rev-parse", "--verify", "--quiet", ref) }.isSuccess
}
