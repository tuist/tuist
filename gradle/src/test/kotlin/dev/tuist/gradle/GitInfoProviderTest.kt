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

    @Test
    fun `ref prefers GITHUB_REF over git describe`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { key ->
                when (key) {
                    "GITHUB_REF" -> "refs/pull/123/merge"
                    else -> null
                }
            },
            gitCommandRunner = { "v1.0.0" }
        )

        assertEquals("refs/pull/123/merge", provider.ref())
    }

    @Test
    fun `ref falls back to git describe when no CI env vars`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { null },
            gitCommandRunner = { args ->
                when (args.first()) {
                    "describe" -> "v1.0.0"
                    else -> "fallback"
                }
            }
        )

        assertEquals("v1.0.0", provider.ref())
    }

    @Test
    fun `ref returns null when git fails and no CI env vars`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { null },
            gitCommandRunner = { throw RuntimeException("git not found") }
        )

        assertEquals(null, provider.ref())
    }

    @Test
    fun `remoteUrlOrigin returns git remote origin URL`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { null },
            gitCommandRunner = { args ->
                if (args.contains("remote.origin.url")) "https://github.com/tuist/tuist.git"
                else "fallback"
            }
        )

        assertEquals("https://github.com/tuist/tuist.git", provider.remoteUrlOrigin())
    }

    @Test
    fun `remoteUrlOrigin returns null when git fails`() {
        val provider = ProcessGitInfoProvider(
            environmentProvider = { null },
            gitCommandRunner = { throw RuntimeException("git not found") }
        )

        assertEquals(null, provider.remoteUrlOrigin())
    }

    private fun mergeCheckout(ref: String?, githubSha: String? = null, secondParent: () -> String) = ProcessGitInfoProvider(
        environmentProvider = { key ->
            when (key) {
                "GITHUB_REF" -> ref
                "GITHUB_SHA" -> githubSha
                else -> null
            }
        },
        gitCommandRunner = { args ->
            when (args) {
                listOf("cat-file", "-p", "HEAD") -> rawMergeCommit(secondParent())
                listOf("rev-parse", "HEAD") -> "merge-commit"
                else -> throw RuntimeException("unexpected git ${args.joinToString(" ")}")
            }
        }
    )

    private fun rawMergeCommit(secondParent: String) =
        "tree t\nparent base\nparent $secondParent\nauthor A <a@tuist.dev> 1700000000 +0000\n" +
            "committer A <a@tuist.dev> 1700000000 +0000\n\nMerge $secondParent into base\nparent message\n"

    @Test
    fun `commitSha is HEAD on a pull request ref without GitHub's merge commit`() {
        // Only GITHUB_SHA says HEAD is GitHub's merge commit.
        assertEquals("merge-commit", mergeCheckout("refs/pull/123/merge") { "pull-request-head" }.commitSha())
    }

    @Test
    fun `commitSha is the pull request's head when HEAD is GitHub's merge commit`() {
        assertEquals(
            "pull-request-head",
            mergeCheckout("refs/pull/123/merge", githubSha = "merge-commit") { "pull-request-head" }.commitSha()
        )
    }

    @Test
    fun `commitSha is HEAD when the workflow checked out another commit than GitHub's merge commit`() {
        // A checkout of the pull request's head keeps GITHUB_REF at the merge ref; when that head is
        // itself a merge commit, its second parent is not the pull request.
        assertEquals(
            "merge-commit",
            mergeCheckout("refs/pull/123/merge", githubSha = "another-commit") { "main" }.commitSha()
        )
    }

    @Test
    fun `commitSha falls back to HEAD when HEAD's commit object cannot be read`() {
        assertEquals(
            "merge-commit",
            mergeCheckout("refs/pull/123/merge", githubSha = "merge-commit") { throw RuntimeException("unreadable") }.commitSha()
        )
    }

    @Test
    fun `commitSha is HEAD outside a pull request ref`() {
        for (ref in listOf("refs/heads/main", null)) {
            assertEquals("merge-commit", mergeCheckout(ref, githubSha = "merge-commit") { "pull-request-head" }.commitSha())
        }
    }
}
