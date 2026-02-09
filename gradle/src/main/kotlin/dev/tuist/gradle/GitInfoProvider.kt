package dev.tuist.gradle

interface GitInfoProvider {
    fun branch(): String?
    fun commitSha(): String?
    fun ref(): String?
}

class ProcessGitInfoProvider : GitInfoProvider {
    override fun branch(): String? = runCatching { runGitCommand("rev-parse", "--abbrev-ref", "HEAD") }.getOrNull()
    override fun commitSha(): String? = runCatching { runGitCommand("rev-parse", "HEAD") }.getOrNull()
    override fun ref(): String? = runCatching { runGitCommand("describe", "--tags", "--always") }.getOrNull()

    private fun runGitCommand(vararg args: String): String {
        val process = ProcessBuilder(listOf("git") + args)
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().readLine()?.trim()
        val exitCode = process.waitFor()
        if (exitCode != 0 || output.isNullOrBlank()) {
            throw RuntimeException("git ${args.first()} failed (exit code $exitCode)")
        }
        return output
    }
}
