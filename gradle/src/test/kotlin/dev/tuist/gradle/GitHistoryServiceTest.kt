package dev.tuist.gradle

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GitHistoryServiceTest {

    @TempDir
    lateinit var workingDirectory: File

    private lateinit var server: MockWebServer
    private val requests = CopyOnWriteArrayList<RecordedRequest>()
    private var settingsResponse: MockResponse = MockResponse().setResponseCode(404)
    private var missing: (List<String>) -> List<String> = { it }

    private val observedAt = Instant.parse("2026-10-15T10:00:00.123Z")
    private val apiPath = "/api/projects/test-account/test-project/tests/git-history"

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                requests += request
                return when (request.path) {
                    "$apiPath/settings" -> settingsResponse
                    "$apiPath/commits/missing" -> {
                        val shas = json(request).getAsJsonArray("shas").map { it.asString }
                        val body = JsonObject().apply {
                            add("missing", com.google.gson.Gson().toJsonTree(missing(shas)))
                        }
                        MockResponse().setResponseCode(200).setBody(body.toString())
                    }
                    "$apiPath/commits" -> MockResponse().setResponseCode(204)
                    else -> MockResponse().setResponseCode(404)
                }
            }
        }
        server.start()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    private fun json(request: RecordedRequest): JsonObject =
        JsonParser.parseString(request.body.clone().readUtf8()).asJsonObject

    private class FakeReader(
        private val repository: Boolean = true,
        private val history: (String, String?, GitHistoryLimits) -> GitHistory
    ) : GitHistoryReading {
        val limits = mutableListOf<GitHistoryLimits>()

        override fun isRepository(): Boolean = repository

        override fun read(headSha: String, baseBranch: String?, limits: GitHistoryLimits): GitHistory {
            this.limits += limits
            return history(headSha, baseBranch, limits)
        }
    }

    private fun history(
        commits: List<GitHistoryCommit> = listOf(
            GitHistoryCommit("mainhead", listOf("base"), 3),
            GitHistoryCommit("head", listOf("base"), 2),
            GitHistoryCommit("base", emptyList(), 1)
        ),
        baseBranch: String? = "main",
        baseHeadSha: String? = "mainhead"
    ) = GitHistory(
        objectFormat = "sha1",
        headSha = "head",
        baseBranch = baseBranch,
        mergeBaseSha = "base",
        baseHeadSha = baseHeadSha,
        commits = commits,
        fallbackReason = null
    )

    private fun service(
        reader: GitHistoryReading = FakeReader { _, _, _ -> history() },
        environment: Map<String, String> = mapOf("GITHUB_BASE_REF" to "main")
    ): GitHistoryService {
        val baseUrl = server.url("/").toString().trimEnd('/')
        val httpClient = TuistHttpClient(
            configurationProvider = object : ConfigurationProvider {
                override fun getConfiguration(forceRefresh: Boolean) = CacheConfiguration(
                    url = baseUrl,
                    token = "test-token",
                    accountHandle = "test-account",
                    projectHandle = "test-project"
                )
            },
            httpClients = TuistHttpClients(useEnvironmentProxy = false),
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )
        return GitHistoryService(
            httpClient = httpClient,
            baseUrl = baseUrl,
            environment = environment,
            reader = { reader },
            clock = { observedAt }
        )
    }

    private val pullRequest = GitInfo(
        branch = "feature",
        commitSha = "head",
        ref = "refs/pull/7/merge",
        remoteUrlOrigin = "git@github.com:acme/app.git"
    )

    @Test
    fun `collects nothing outside CI`() {
        val collected = service().collect(pullRequest, workingDirectory, isCi = false)

        assertNull(collected)
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `collects nothing when the upload is disabled`() {
        for (value in listOf("false", "FALSE", "0", "no", "NO")) {
            val collected = service(environment = mapOf("TUIST_GIT_UPLOAD_ENABLED" to value))
                .collect(pullRequest, workingDirectory, isCi = true)

            assertNull(collected, "TUIST_GIT_UPLOAD_ENABLED=$value")
        }
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `collects the history with the server's settings`() {
        settingsResponse = MockResponse().setResponseCode(200).setBody(
            """{"window_days":30,"window_commits":100,"deepen_budget_seconds":10,"upload_batch_size":2,"commit_file_limit":3}"""
        )
        val reader = FakeReader { _, _, _ -> history() }

        val collected = assertNotNull(
            service(reader = reader, environment = mapOf("TUIST_GIT_UPLOAD_ENABLED" to "true", "GITHUB_BASE_REF" to "main"))
                .collect(pullRequest, workingDirectory, isCi = true)
        )

        assertEquals(listOf(GitHistoryLimits(windowDays = 30, windowCommits = 100, deepenBudgetSeconds = 10, unshallow = true)), reader.limits)
        assertEquals(
            TestRunGitHistory(
                baseBranch = "main",
                mergeBaseSha = "base",
                isPullRequest = true,
                pullRequestNumber = 7,
                objectFormat = "sha1",
                source = "client",
                fallbackReason = null
            ),
            collected.payload
        )
        assertEquals(2, collected.settings.uploadBatchSize)
        assertEquals("git@github.com:acme/app.git", collected.repositoryUrl)
        assertEquals(observedAt, collected.observedAt)
        assertEquals("Bearer test-token", requests.single().getHeader("Authorization"))
    }

    @Test
    fun `falls back to the default settings when the server has none`() {
        val reader = FakeReader { _, _, _ -> history() }

        val collected = assertNotNull(service(reader = reader).collect(pullRequest, workingDirectory, isCi = true))

        assertEquals(listOf(GitHistoryLimits()), reader.limits)
        assertEquals(500, collected.settings.uploadBatchSize)
    }

    @Test
    fun `reads the checkout without fetching when unshallowing is disabled`() {
        val reader = FakeReader { _, _, _ -> history() }

        service(reader = reader, environment = mapOf("TUIST_GIT_UNSHALLOW_ENABLED" to "false"))
            .collect(pullRequest, workingDirectory, isCi = true)

        assertEquals(false, reader.limits.single().unshallow)
    }

    @Test
    fun `reports a run outside a repository as historyless but keeps its pull request`() {
        val collected = assertNotNull(
            service(reader = FakeReader(repository = false) { _, _, _ -> error("not read") })
                .collect(pullRequest, workingDirectory, isCi = true)
        )

        assertEquals(
            TestRunGitHistory(
                baseBranch = "main",
                mergeBaseSha = null,
                isPullRequest = true,
                pullRequestNumber = 7,
                objectFormat = null,
                source = "none",
                fallbackReason = "the working directory is not a Git repository"
            ),
            collected.payload
        )
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `reports a run without a commit as historyless`() {
        val collected = assertNotNull(
            service().collect(pullRequest.copy(commitSha = null), workingDirectory, isCi = true)
        )

        assertEquals("none", collected.payload.source)
        assertEquals("the run's commit is unknown", collected.payload.fallbackReason)
    }

    @Test
    fun `reports a history that could not be read as historyless`() {
        val reader = FakeReader { _, _, _ -> throw GitCommandException("git log failed (exit code 128)") }

        val collected = assertNotNull(service(reader = reader).collect(pullRequest, workingDirectory, isCi = true))

        assertEquals("none", collected.payload.source)
        assertEquals("git log failed (exit code 128)", collected.payload.fallbackReason)
        assertEquals("main", collected.payload.baseBranch)
        assertEquals(7, collected.payload.pullRequestNumber)
        assertNull(collected.payload.objectFormat)
    }

    @Test
    fun `uploads the missing commits oldest first in batches with the branch heads on the last`() {
        settingsResponse = MockResponse().setResponseCode(200).setBody(
            """{"window_days":365,"window_commits":5000,"deepen_budget_seconds":60,"upload_batch_size":2,"commit_file_limit":3}"""
        )
        val subject = service()
        val collected = subject.collect(pullRequest, workingDirectory, isCi = true)
        requests.clear()

        subject.upload(collected)

        assertEquals(
            listOf("$apiPath/commits/missing", "$apiPath/commits", "$apiPath/commits"),
            requests.map { it.path }
        )
        val missingRequest = json(requests[0])
        assertEquals("git@github.com:acme/app.git", missingRequest.get("repository_url").asString)
        assertEquals(listOf("mainhead", "head", "base"), missingRequest.getAsJsonArray("shas").map { it.asString })

        val first = json(requests[1])
        assertEquals("sha1", first.get("object_format").asString)
        assertEquals("git@github.com:acme/app.git", first.get("repository_url").asString)
        assertEquals(listOf("base", "head"), first.getAsJsonArray("commits").map { it.asJsonObject.get("sha").asString })
        assertEquals(0, first.getAsJsonArray("branch_heads").size())
        val head = first.getAsJsonArray("commits")[1].asJsonObject
        assertEquals(listOf("base"), head.getAsJsonArray("parents").map { it.asString })
        assertEquals("1970-01-01T00:00:02Z", head.get("committed_at").asString)

        val last = json(requests[2])
        assertEquals(listOf("mainhead"), last.getAsJsonArray("commits").map { it.asJsonObject.get("sha").asString })
        assertEquals(
            listOf(
                Triple("feature", "head", "2026-10-15T10:00:00.123Z"),
                Triple("main", "mainhead", "2026-10-15T10:00:00.123Z")
            ),
            last.getAsJsonArray("branch_heads").map {
                val branchHead = it.asJsonObject
                Triple(branchHead.get("branch").asString, branchHead.get("sha").asString, branchHead.get("observed_at").asString)
            }
        )
    }

    @Test
    fun `posts the branch heads even when the server has every commit`() {
        missing = { emptyList() }
        val subject = service()
        val collected = subject.collect(pullRequest, workingDirectory, isCi = true)
        requests.clear()

        subject.upload(collected)

        assertEquals(listOf("$apiPath/commits/missing", "$apiPath/commits"), requests.map { it.path })
        val upload = json(requests[1])
        assertEquals(0, upload.getAsJsonArray("commits").size())
        assertEquals(
            listOf("feature", "main"),
            upload.getAsJsonArray("branch_heads").map { it.asJsonObject.get("branch").asString }
        )
    }

    @Test
    fun `reports the base branch head only when the history lists it`() {
        missing = { emptyList() }
        val subject = service(reader = FakeReader { _, _, _ -> history(baseHeadSha = "unlisted") })
        val collected = subject.collect(pullRequest, workingDirectory, isCi = true)
        requests.clear()

        subject.upload(collected)

        assertEquals(
            listOf("feature"),
            json(requests.last()).getAsJsonArray("branch_heads").map { it.asJsonObject.get("branch").asString }
        )
    }

    @Test
    fun `reports one head when the run is on the base branch`() {
        missing = { emptyList() }
        val push = pullRequest.copy(branch = "main", ref = "refs/heads/main")
        val subject = service(environment = mapOf("GITHUB_BASE_REF" to "main"))
        val collected = subject.collect(push, workingDirectory, isCi = true)
        requests.clear()

        subject.upload(collected)

        assertEquals(
            listOf("main" to "head"),
            json(requests.last()).getAsJsonArray("branch_heads").map {
                it.asJsonObject.get("branch").asString to it.asJsonObject.get("sha").asString
            }
        )
    }

    @Test
    fun `never moves the branch to a head the history does not list`() {
        val subject = service(reader = FakeReader { _, _, _ -> history(commits = emptyList()) })
        val collected = subject.collect(pullRequest, workingDirectory, isCi = true)
        requests.clear()

        subject.upload(collected)

        assertTrue(requests.isEmpty())
    }

    @Test
    fun `uploads nothing without a remote`() {
        val subject = service()
        val collected = subject.collect(pullRequest.copy(remoteUrlOrigin = null), workingDirectory, isCi = true)
        requests.clear()

        subject.upload(collected)

        assertTrue(requests.isEmpty())
    }

    @Test
    fun `asks for the missing commits in requests the server accepts`() {
        missing = { emptyList() }
        val commits = (0 until 6_001).map { GitHistoryCommit("sha$it", emptyList(), it.toLong()) }
        val subject = service(reader = FakeReader { _, _, _ -> history(commits = commits) })
        val collected = subject.collect(pullRequest, workingDirectory, isCi = true)
        requests.clear()

        subject.upload(collected)

        val missingRequests = requests.filter { it.path == "$apiPath/commits/missing" }
        assertEquals(listOf(5_000, 1_001), missingRequests.map { json(it).getAsJsonArray("shas").size() })
    }

    @Test
    fun `an upload failure is not thrown`() {
        val subject = service()
        val collected = subject.collect(pullRequest, workingDirectory, isCi = true)
        server.shutdown()

        subject.upload(collected)
    }

    @Test
    fun `the environment names the base branch and the pull request`() {
        assertEquals("main", GitHistoryEnvironment(mapOf("SYSTEM_PULLREQUEST_TARGETBRANCH" to "refs/heads/main")).baseBranch())
        assertEquals(
            "develop",
            GitHistoryEnvironment(mapOf("GITHUB_BASE_REF" to "", "CI_MERGE_REQUEST_TARGET_BRANCH_NAME" to "develop")).baseBranch()
        )
        assertNull(GitHistoryEnvironment(emptyMap()).baseBranch())

        assertEquals(12, GitHistoryEnvironment(emptyMap()).pullRequestNumber("refs/pull/12/merge"))
        assertEquals(3, GitHistoryEnvironment(emptyMap()).pullRequestNumber("refs/merge-requests/3/head"))
        assertEquals(5, GitHistoryEnvironment(mapOf("CI_MERGE_REQUEST_IID" to "5")).pullRequestNumber("refs/heads/feature"))
        assertEquals(9, GitHistoryEnvironment(mapOf("BUILDKITE_PULL_REQUEST" to "9")).pullRequestNumber(null))
        assertNull(GitHistoryEnvironment(mapOf("BUILDKITE_PULL_REQUEST" to "false")).pullRequestNumber(null))
        assertNull(GitHistoryEnvironment(mapOf("CI_PULL_REQUEST_NUMBER" to "0")).pullRequestNumber(null))
    }

    @Test
    fun `history is enabled on CI unless turned off`() {
        assertTrue(GitHistoryEnvironment(emptyMap()).enabled(isCi = true))
        assertTrue(GitHistoryEnvironment(mapOf("TUIST_GIT_UPLOAD_ENABLED" to "1")).enabled(isCi = true))
        assertEquals(false, GitHistoryEnvironment(emptyMap()).enabled(isCi = false))
        assertEquals(false, GitHistoryEnvironment(mapOf("TUIST_GIT_UPLOAD_ENABLED" to "no")).enabled(isCi = true))
        assertTrue(GitHistoryEnvironment(emptyMap()).unshallowEnabled())
        assertEquals(false, GitHistoryEnvironment(mapOf("TUIST_GIT_UNSHALLOW_ENABLED" to "0")).unshallowEnabled())
    }
}
