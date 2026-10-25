package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.gradle.api.logging.Logging
import java.io.File
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI
import java.time.Instant
import java.time.temporal.ChronoUnit

/** The fields a test run reports about its Git history. */
data class TestRunGitHistory(
    val baseBranch: String?,
    val mergeBaseSha: String?,
    val isPullRequest: Boolean,
    val pullRequestNumber: Int?,
    val objectFormat: String?,
    /** `client` when the history was read from the checkout, `none` when it could not be. */
    val source: String,
    val fallbackReason: String?
)

data class GitHistorySettings(
    val windowDays: Int = 365,
    val windowCommits: Int = 5000,
    val deepenBudgetSeconds: Int = 60,
    val uploadBatchSize: Int = 500
)

/** A run's Git history as collected from the checkout, with what is needed to upload it once the run exists. */
data class CollectedGitHistory(
    val payload: TestRunGitHistory,
    /** Null when nothing could be read from the checkout. */
    val history: GitHistory?,
    val branch: String?,
    /** The remote the repository is known by on the server. */
    val repositoryUrl: String?,
    val settings: GitHistorySettings,
    /** When the checkout was read: the server moves a branch only on an observation no older than the one that last moved it. */
    val observedAt: Instant
)

/** Reads what the CI environment says about a run's Git history, and whether to collect it. */
class GitHistoryEnvironment(private val environment: Map<String, String>) {
    fun enabled(isCi: Boolean): Boolean = isCi && !isFalsy("TUIST_GIT_UPLOAD_ENABLED")

    /** `TUIST_GIT_UNSHALLOW_ENABLED=false` keeps collection to what the checkout has. */
    fun remoteAccess(): GitHistoryRemoteAccess =
        if (isFalsy("TUIST_GIT_UNSHALLOW_ENABLED")) GitHistoryRemoteAccess.NONE else GitHistoryRemoteAccess.BASE_HEAD

    /** The branch a pull request merges into, from the CI provider only: a checkout does not know it. */
    fun baseBranch(): String? = firstValue(baseBranchVariables)?.removePrefix("refs/heads/")

    fun pullRequestNumber(ref: String?): Int? {
        val fromRef = ref?.let { pullRequestRef.find(it)?.groupValues?.get(1) }
        return (fromRef ?: firstValue(pullRequestVariables))?.toIntOrNull()?.takeIf { it > 0 }
    }

    private fun firstValue(names: List<String>): String? =
        names.firstNotNullOfOrNull { name -> environment[name]?.takeIf { it.isNotEmpty() } }

    private fun isFalsy(name: String): Boolean = environment[name] in falsyValues

    companion object {
        private val falsyValues = setOf("0", "false", "FALSE", "no", "NO")

        private val pullRequestRef = Regex("^refs/(?:pull|merge-requests)/(\\d+)/")

        private val baseBranchVariables = listOf(
            // GitHub Actions
            "GITHUB_BASE_REF",
            // GitLab CI
            "CI_MERGE_REQUEST_TARGET_BRANCH_NAME",
            "CI_EXTERNAL_PULL_REQUEST_TARGET_BRANCH_NAME",
            // Bitrise
            "BITRISEIO_GIT_BRANCH_DEST",
            // Buildkite
            "BUILDKITE_PULL_REQUEST_BASE_BRANCH",
            // Codemagic
            "CM_PULL_REQUEST_DEST",
            // Xcode Cloud
            "CI_PULL_REQUEST_TARGET_BRANCH",
            // Azure DevOps (a full ref, refs/heads/main)
            "SYSTEM_PULLREQUEST_TARGETBRANCH",
        )

        private val pullRequestVariables = listOf(
            // Codemagic
            "CM_PULL_REQUEST_NUMBER",
            // GitLab CI
            "CI_EXTERNAL_PULL_REQUEST_IID",
            // Bitrise
            "BITRISE_PULL_REQUEST",
            // AppCircle
            "AC_PULL_NUMBER",
            // Xcode Cloud
            "CI_PULL_REQUEST_NUMBER",
            // Buildkite
            "BUILDKITE_PULL_REQUEST",
            // CircleCI
            "CIRCLE_PR_NUMBER",
            // GitLab CI
            "CI_MERGE_REQUEST_IID",
        )
    }
}

/**
 * Collects a CI run's Git history from the checkout within the limits the server sets, and
 * uploads the commits the server's graph lacks with the branch heads the checkout saw. Both are
 * best effort: a history problem never fails or loses a run, and what could not be collected is
 * reported with the run.
 */
class GitHistoryService(
    private val httpClient: TuistHttpClient,
    private val baseUrl: String,
    private val environment: Map<String, String> = System.getenv(),
    private val reader: (File) -> GitHistoryReading = { GitHistoryReader(ProcessGitRunner(it), it) },
    private val clock: () -> Instant = Instant::now
) {
    private val logger = Logging.getLogger(GitHistoryService::class.java)
    private val gson = Gson()

    fun collect(gitInfo: GitInfoProvider, workingDirectory: File, isCi: Boolean): CollectedGitHistory? {
        val gitEnvironment = GitHistoryEnvironment(environment)
        if (!gitEnvironment.enabled(isCi)) return null
        val observedAt = clock()
        val ref = gitInfo.ref()
        val baseBranch = gitEnvironment.baseBranch()
        val pullRequestNumber = gitEnvironment.pullRequestNumber(ref)
        val isPullRequest = pullRequestNumber != null || ref?.startsWith("refs/pull/") == true

        // Without a history the run still says why, and keeps the pull request identity CI provided.
        fun historyless(reason: String, settings: GitHistorySettings) = CollectedGitHistory(
            payload = TestRunGitHistory(
                baseBranch = baseBranch,
                mergeBaseSha = null,
                isPullRequest = isPullRequest,
                pullRequestNumber = pullRequestNumber,
                objectFormat = null,
                source = "none",
                fallbackReason = reason
            ),
            history = null,
            branch = gitInfo.branch(),
            repositoryUrl = gitInfo.remoteUrlOrigin(),
            settings = settings,
            observedAt = observedAt
        )

        val headSha = gitInfo.commitSha() ?: return historyless("the run's commit is unknown", GitHistorySettings())
        val reader = reader(workingDirectory)
        if (!reader.isRepository()) {
            return historyless("the working directory is not a Git repository", GitHistorySettings())
        }

        val settings = settings()
        val history = try {
            reader.read(
                headSha = headSha,
                baseBranch = baseBranch,
                limits = GitHistoryLimits(
                    windowDays = settings.windowDays,
                    windowCommits = settings.windowCommits,
                    deepenBudgetSeconds = settings.deepenBudgetSeconds,
                    remoteAccess = gitEnvironment.remoteAccess()
                )
            )
        } catch (e: Exception) {
            val reason = e.message ?: e.javaClass.simpleName
            logger.info("Tuist: The run's Git history could not be read: $reason")
            return historyless(reason, settings)
        }

        return CollectedGitHistory(
            payload = TestRunGitHistory(
                baseBranch = history.baseBranch,
                mergeBaseSha = history.mergeBaseSha,
                isPullRequest = isPullRequest,
                pullRequestNumber = pullRequestNumber,
                objectFormat = history.objectFormat,
                source = "client",
                fallbackReason = history.fallbackReason
            ),
            history = history,
            branch = gitInfo.branch(),
            repositoryUrl = gitInfo.remoteUrlOrigin(),
            settings = settings,
            observedAt = observedAt
        )
    }

    /**
     * Sends the commits the server lacks, oldest first so their generation numbers are exact, in
     * batches of the server's size, with the run's branch head and the base branch's as the
     * checkout saw it on the last batch. The repository is named by its remote, so a checkout
     * without one has no graph to upload to. Returns false when the upload failed.
     */
    fun upload(collected: CollectedGitHistory?): Boolean {
        val history = collected?.history ?: return true
        val repositoryUrl = collected.repositoryUrl?.takeIf { it.isNotBlank() } ?: return true
        return try {
            uploadCommits(collected, history, repositoryUrl)
            true
        } catch (e: Exception) {
            logger.info("Tuist: The run's Git history could not be uploaded: ${e.message}")
            false
        }
    }

    private fun uploadCommits(collected: CollectedGitHistory, history: GitHistory, repositoryUrl: String) {
        val commits = history.commits
        if (commits.isEmpty()) return

        val missing = commits.map { it.sha }.chunked(MISSING_COMMITS_BATCH_SIZE).flatMapTo(mutableSetOf()) { shas ->
            request("commits/missing", MissingCommitsRequest(repositoryUrl, shas)) { connection ->
                InputStreamReader(connection.inputStream, Charsets.UTF_8).use {
                    gson.fromJson(it, MissingCommitsResponse::class.java)?.missing.orEmpty()
                }
            }
        }

        // Reversed first so that, between commits with the same time, the older listed one goes first.
        val toUpload = commits.reversed().filter { it.sha in missing }.sortedBy { it.committedAt }.map {
            CommitPayload(sha = it.sha, parents = it.parents, committedAt = Instant.ofEpochSecond(it.committedAt).toString())
        }

        val observedAt = collected.observedAt.truncatedTo(ChronoUnit.MILLIS).toString()
        val branchHeads = mutableListOf<BranchHeadPayload>()
        collected.branch?.let { branchHeads += BranchHeadPayload(it, history.headSha, observedAt) }
        // A pull request's run is how the base branch's head is seen between the base branch's own
        // runs. The checkout may not have that commit: the run that tested it, a merge queue's
        // typically, sent it already.
        val baseBranch = history.baseBranch
        val baseHeadSha = history.baseHeadSha
        if (baseBranch != null && baseBranch != collected.branch && baseHeadSha != null) {
            branchHeads += BranchHeadPayload(baseBranch, baseHeadSha, observedAt)
        }

        val batches = toUpload.chunked(collected.settings.uploadBatchSize.coerceIn(1, MAX_UPLOAD_BATCH_SIZE))
        if (batches.isEmpty()) {
            if (branchHeads.isNotEmpty()) {
                request("commits", UploadCommitsRequest(repositoryUrl, history.objectFormat, emptyList(), branchHeads)) {}
            }
            return
        }
        batches.forEachIndexed { index, batch ->
            val heads = if (index == batches.lastIndex) branchHeads else emptyList()
            request("commits", UploadCommitsRequest(repositoryUrl, history.objectFormat, batch, heads)) {}
        }
    }

    private fun settings(): GitHistorySettings {
        val defaults = GitHistorySettings()
        return try {
            val response = request("settings", null) { connection ->
                InputStreamReader(connection.inputStream, Charsets.UTF_8).use {
                    gson.fromJson(it, GitHistorySettingsResponse::class.java)
                }
            }
            GitHistorySettings(
                windowDays = response?.windowDays ?: defaults.windowDays,
                windowCommits = response?.windowCommits ?: defaults.windowCommits,
                deepenBudgetSeconds = response?.deepenBudgetSeconds ?: defaults.deepenBudgetSeconds,
                uploadBatchSize = response?.uploadBatchSize ?: defaults.uploadBatchSize
            )
        } catch (e: Exception) {
            logger.debug("Tuist: Using the default Git history settings: ${e.message}")
            defaults
        }
    }

    /** Every history request can be sent again: lookups only read, and uploads skip commits and heads already stored. */
    private fun <T> request(path: String, body: Any?, onSuccess: (HttpURLConnection) -> T): T =
        httpClient.execute { config ->
            val url = URI(baseUrl.trimEnd('/'))
                .resolve("/api/projects/${config.accountHandle}/${config.projectHandle}/tests/git-history/$path")
            httpClient.retrying("Git history request to $path", replaySafe = true) {
                val connection = httpClient.openConnection(url, config)
                try {
                    connection.setRequestProperty("Accept", "application/json")
                    if (body == null) {
                        connection.requestMethod = "GET"
                    } else {
                        connection.requestMethod = "POST"
                        connection.doOutput = true
                        connection.setRequestProperty("Content-Type", "application/json")
                        OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { gson.toJson(body, it) }
                    }
                    when (val status = connection.responseCode) {
                        in 200..299 -> onSuccess(connection)
                        HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                        else -> throw TuistRetry.statusFailure(connection, status) {
                            IOException("the server responded to $path with HTTP $status")
                        }
                    }
                } finally {
                    connection.disconnect()
                }
            }
        }

    private data class GitHistorySettingsResponse(
        @SerializedName("window_days") val windowDays: Int?,
        @SerializedName("window_commits") val windowCommits: Int?,
        @SerializedName("deepen_budget_seconds") val deepenBudgetSeconds: Int?,
        @SerializedName("upload_batch_size") val uploadBatchSize: Int?
    )

    private data class MissingCommitsRequest(
        @SerializedName("repository_url") val repositoryUrl: String,
        val shas: List<String>
    )

    private data class MissingCommitsResponse(val missing: List<String>?)

    private data class UploadCommitsRequest(
        @SerializedName("repository_url") val repositoryUrl: String,
        @SerializedName("object_format") val objectFormat: String,
        val commits: List<CommitPayload>,
        @SerializedName("branch_heads") val branchHeads: List<BranchHeadPayload>
    )

    private data class CommitPayload(
        val sha: String,
        val parents: List<String>,
        @SerializedName("committed_at") val committedAt: String
    )

    private data class BranchHeadPayload(
        val branch: String,
        val sha: String,
        @SerializedName("observed_at") val observedAt: String
    )

    companion object {
        /** SHAs per missing-commits request; the server accepts up to 10,000. */
        private const val MISSING_COMMITS_BATCH_SIZE = 5_000

        /** Commits per upload request the server accepts. */
        private const val MAX_UPLOAD_BATCH_SIZE = 10_000
    }
}

/**
 * A build's history, collected once and published once, before the server is asked anything that
 * reads the commit graph: the stress gate's plan and the run's report. Publishing is recorded only
 * once the upload succeeded, so a failed early attempt is retried before the report.
 */
class GitHistoryPublisher(
    private val collect: () -> CollectedGitHistory?,
    private val upload: (CollectedGitHistory?) -> Boolean
) {
    private var collected: CollectedGitHistory? = null
    private var hasCollected = false
    private var published = false

    @Synchronized
    fun publish(): CollectedGitHistory? {
        if (!hasCollected) {
            collected = collect()
            hasCollected = true
        }
        if (!published) published = upload(collected)
        return collected
    }
}
