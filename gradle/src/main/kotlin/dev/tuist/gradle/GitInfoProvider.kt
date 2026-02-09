package dev.tuist.gradle

interface GitInfoProvider {
    fun branch(): String?
    fun commitSha(): String?
    fun ref(): String?
}

class ProcessGitInfoProvider : GitInfoProvider {
    override fun branch(): String? = runGitCommand("rev-parse", "--abbrev-ref", "HEAD")
    override fun commitSha(): String? = runGitCommand("rev-parse", "HEAD")
    override fun ref(): String? = runGitCommand("describe", "--tags", "--always")

    private fun runGitCommand(vararg args: String): String? {
        return try {
            val process = ProcessBuilder(listOf("git") + args)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().readLine()?.trim()
            val exitCode = process.waitFor()
            if (exitCode == 0 && !output.isNullOrBlank()) output else null
        } catch (e: Exception) {
            null
        }
    }
}
