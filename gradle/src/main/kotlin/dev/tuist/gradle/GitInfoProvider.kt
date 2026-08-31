package dev.tuist.gradle

interface GitInfoProvider {
    fun branch(): String?
    fun commitSha(): String?
    fun ref(): String?
    fun remoteUrlOrigin(): String?
    fun isDirty(): Boolean? = null
}

class ProcessGitInfoProvider(
    private val environmentProvider: (String) -> String? = { System.getenv(it) },
    private val gitCommandRunner: (List<String>) -> String = ::runGitProcess
) : GitInfoProvider {

    override fun branch(): String? {
        val gitBranch =
            runCatching { gitCommandRunner(listOf("rev-parse", "--abbrev-ref", "HEAD")) }
                .getOrNull()
                ?.takeIf(String::isNotBlank)
        if (gitBranch != null && gitBranch != "HEAD") {
            return gitBranch
        }
        return ciBranch()
    }

    override fun commitSha(): String? =
        runCatching { gitCommandRunner(listOf("rev-parse", "HEAD")) }.getOrNull()?.takeIf(String::isNotBlank)

    override fun ref(): String? {
        val ciRef = ciRef()
        if (ciRef != null) return ciRef
        return runCatching { gitCommandRunner(listOf("describe", "--tags", "--always")) }.getOrNull()?.takeIf(String::isNotBlank)
    }

    override fun remoteUrlOrigin(): String? =
        runCatching { gitCommandRunner(listOf("config", "--get", "remote.origin.url")) }.getOrNull()?.takeIf(String::isNotBlank)

    override fun isDirty(): Boolean? =
        runCatching { gitCommandRunner(listOf("status", "--porcelain")) }
            .getOrNull()
            ?.let(String::isNotBlank)

    private fun ciRef(): String? =
        refEnvironmentVariables
            .mapNotNull { environmentProvider(it) }
            .firstOrNull { it.isNotEmpty() }

    private fun ciBranch(): String? =
        branchEnvironmentVariables
            .mapNotNull { environmentProvider(it) }
            .firstOrNull { it.isNotEmpty() }

    companion object {
        private val refEnvironmentVariables = listOf(
            // GitHub Actions
            "GITHUB_REF",
            // GitLab CI
            "CI_MERGE_REQUEST_REF_PATH",
        )

        private val branchEnvironmentVariables = listOf(
            // GitHub Actions
            "GITHUB_HEAD_REF",
            // GitLab CI
            "CI_COMMIT_REF_NAME",
            // Bitrise
            "BITRISE_GIT_BRANCH",
            // CircleCI
            "CIRCLE_BRANCH",
            // Buildkite
            "BUILDKITE_BRANCH",
            // Codemagic
            "CM_BRANCH",
            // AppCircle
            "AC_GIT_BRANCH",
            // Xcode Cloud
            "CI_BRANCH",
            // TeamCity
            "teamcity.build.branch",
            // Azure DevOps
            "BUILD_SOURCEBRANCHNAME",
        )
    }
}

private fun runGitProcess(args: List<String>): String {
    val process = ProcessBuilder(listOf("git") + args)
        .redirectErrorStream(true)
        .start()
    try {
        val output = process.inputStream.bufferedReader().use { it.readText().trim() }
        val exitCode = process.waitFor()
        if (exitCode != 0) {
            throw RuntimeException("git ${args.first()} failed (exit code $exitCode)")
        }
        return output
    } catch (e: Exception) {
        process.destroyForcibly()
        throw e
    }
}
