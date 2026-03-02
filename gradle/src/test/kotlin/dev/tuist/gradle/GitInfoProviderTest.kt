package dev.tuist.gradle

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class GitInfoProviderTest {

    @Test
    fun `branch prefers CI environment variable over HEAD`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { key ->
                when (key) {
                    "GITHUB_HEAD_REF" -> "feature/my-pr-branch"
                    else -> null
                }
            },
            gitCommandRunner = { "HEAD" }
        )

        assertEquals("feature/my-pr-branch", provider.branch())
    }

    @Test
    fun `branch returns git command result when not HEAD`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { null },
            gitCommandRunner = { "main" }
        )

        assertEquals("main", provider.branch())
    }

    @Test
    fun `branch returns git command result when no CI env vars set and on a real branch`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { null },
            gitCommandRunner = { "feature/local-work" }
        )

        assertEquals("feature/local-work", provider.branch())
    }

    @Test
    fun `branch falls back to CI_COMMIT_REF_NAME for GitLab`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { key ->
                when (key) {
                    "CI_COMMIT_REF_NAME" -> "gitlab-branch"
                    else -> null
                }
            },
            gitCommandRunner = { "HEAD" }
        )

        assertEquals("gitlab-branch", provider.branch())
    }

    @Test
    fun `branch falls back to CIRCLE_BRANCH for CircleCI`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { key ->
                when (key) {
                    "CIRCLE_BRANCH" -> "circle-branch"
                    else -> null
                }
            },
            gitCommandRunner = { "HEAD" }
        )

        assertEquals("circle-branch", provider.branch())
    }

    @Test
    fun `branch skips empty CI env vars`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { key ->
                when (key) {
                    "GITHUB_HEAD_REF" -> ""
                    "CI_COMMIT_REF_NAME" -> "actual-branch"
                    else -> null
                }
            },
            gitCommandRunner = { "HEAD" }
        )

        assertEquals("actual-branch", provider.branch())
    }

    @Test
    fun `branch returns null when git fails and no CI env vars`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { null },
            gitCommandRunner = { throw RuntimeException("git not found") }
        )

        assertEquals(null, provider.branch())
    }

    @Test
    fun `branch returns null when git reports HEAD and no CI env vars`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { null },
            gitCommandRunner = { "HEAD" }
        )

        assertEquals(null, provider.branch())
    }

    @Test
    fun `branch falls back to BUILDKITE_BRANCH for Buildkite`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { key ->
                when (key) {
                    "BUILDKITE_BRANCH" -> "buildkite-branch"
                    else -> null
                }
            },
            gitCommandRunner = { "HEAD" }
        )

        assertEquals("buildkite-branch", provider.branch())
    }

    @Test
    fun `branch falls back to BUILD_SOURCEBRANCHNAME for Azure DevOps`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { key ->
                when (key) {
                    "BUILD_SOURCEBRANCHNAME" -> "azure-branch"
                    else -> null
                }
            },
            gitCommandRunner = { "HEAD" }
        )

        assertEquals("azure-branch", provider.branch())
    }
}
