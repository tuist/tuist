package dev.tuist.gradle

import org.gradle.api.provider.ValueSource
import org.gradle.api.provider.ValueSourceParameters
import org.gradle.process.ExecOperations
import java.io.ByteArrayOutputStream
import java.io.Serializable
import javax.inject.Inject

interface GitInfoProvider {
    fun branch(): String?
    fun commitSha(): String?
    fun ref(): String?
    fun remoteUrlOrigin(): String?
}

object EmptyGitInfoProvider : GitInfoProvider {
    override fun branch(): String? = null
    override fun commitSha(): String? = null
    override fun ref(): String? = null
    override fun remoteUrlOrigin(): String? = null
}

data class GitInfo(
    private val branch: String?,
    private val commitSha: String?,
    private val ref: String?,
    private val remoteUrlOrigin: String?
) : GitInfoProvider, Serializable {
    override fun branch(): String? = branch
    override fun commitSha(): String? = commitSha
    override fun ref(): String? = ref
    override fun remoteUrlOrigin(): String? = remoteUrlOrigin
}

abstract class GitInfoValueSource : ValueSource<GitInfo, ValueSourceParameters.None> {
    @get:Inject
    abstract val execOperations: ExecOperations

    override fun obtain(): GitInfo {
        val provider = ProcessGitInfoProvider(gitCommandRunner = ::runGitCommand)

        return GitInfo(
            branch = provider.branch(),
            commitSha = provider.commitSha(),
            ref = provider.ref(),
            remoteUrlOrigin = provider.remoteUrlOrigin()
        )
    }

    private fun runGitCommand(args: List<String>): String {
        val output = ByteArrayOutputStream()
        val result = execOperations.exec {
            commandLine(listOf("git") + args)
            standardOutput = output
            errorOutput = output
            isIgnoreExitValue = true
        }
        val value = output.toString(Charsets.UTF_8).lineSequence().firstOrNull()?.trim()

        if (result.exitValue != 0 || value.isNullOrBlank()) {
            throw RuntimeException("git ${args.first()} failed (exit code ${result.exitValue})")
        }

        return value
    }
}

class ProcessGitInfoProvider(
    private val environmentProvider: (String) -> String? = { System.getenv(it) },
    private val gitCommandRunner: (List<String>) -> String = ::runGitProcess
) : GitInfoProvider {

    override fun branch(): String? {
        val gitBranch = runCatching { gitCommandRunner(listOf("rev-parse", "--abbrev-ref", "HEAD")) }.getOrNull()
        if (gitBranch != null && gitBranch != "HEAD") {
            return gitBranch
        }
        return ciBranch()
    }

    override fun commitSha(): String? = runCatching { gitCommandRunner(listOf("rev-parse", "HEAD")) }.getOrNull()

    override fun ref(): String? {
        val ciRef = ciRef()
        if (ciRef != null) return ciRef
        return runCatching { gitCommandRunner(listOf("describe", "--tags", "--always")) }.getOrNull()
    }

    override fun remoteUrlOrigin(): String? =
        runCatching { gitCommandRunner(listOf("config", "--get", "remote.origin.url")) }.getOrNull()

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
        val output = process.inputStream.bufferedReader().use { it.readLine()?.trim() }
        val exitCode = process.waitFor()
        if (exitCode != 0 || output.isNullOrBlank()) {
            throw RuntimeException("git ${args.first()} failed (exit code $exitCode)")
        }
        return output
    } catch (e: Exception) {
        process.destroyForcibly()
        throw e
    }
}
