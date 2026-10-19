package dev.tuist.app.data.home

import dev.tuist.app.api.HomeApi
import dev.tuist.app.api.model.HomeActivity
import dev.tuist.app.api.model.HomeActivityItem as ApiItem
import dev.tuist.app.data.EnvironmentConfig
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import retrofit2.Response

class HomeActivityRepositoryTest {
    private val api = mockk<HomeApi>()
    private val environment = mockk<EnvironmentConfig> { every { serverUrl } returns "https://example.invalid:8443/deployment" }
    private val subject = HomeActivityRepository(api, environment)

    @Test fun `requests each project-scoped endpoint and bounds the response`() = runTest {
        val body = HomeActivity(items = (1..5).map { index ->
            ApiItem(id = "$index", title = "AppTests", subtitle = "main", occurredAt = 2_200_000_000L,
                url = "/sample/one/tests/test-runs/$index")
        })
        coEvery { api.getHomeBuildFailures("sample", "one") } returns Response.success(body)
        coEvery { api.getHomeTestFailures("sample", "one") } returns Response.success(body)
        coEvery { api.getHomeFlakyTests("sample", "one") } returns Response.success(body)

        HomeActivityKind.entries.forEach { kind ->
            val items = subject.list(kind, "sample/one")
            assertEquals(3, items.size)
            assertEquals(2_200_000_000L, items.first().occurredAt)
            assertEquals("https://example.invalid:8443/deployment/sample/one/tests/test-runs/1", items.first().url)
        }
        coVerify(exactly = 1) { api.getHomeBuildFailures("sample", "one") }
        coVerify(exactly = 1) { api.getHomeTestFailures("sample", "one") }
        coVerify(exactly = 1) { api.getHomeFlakyTests("sample", "one") }
    }

    @Test fun `old-server and HTTP errors never produce healthy empty results`() = runTest {
        for ((status, reason) in listOf(404 to HomeActivityFailure.Unavailable, 500 to HomeActivityFailure.Unavailable,
            403 to HomeActivityFailure.Forbidden, 422 to HomeActivityFailure.Unsupported)) {
            coEvery { api.getHomeBuildFailures("sample", "one") } returns Response.error(status, "{}".toResponseBody())
            val error = runCatching { subject.list(HomeActivityKind.BuildFailures, "sample/one") }.exceptionOrNull()
            assertEquals(reason, (error as HomeActivityException).failure)
        }
        coEvery { api.getHomeBuildFailures("sample", "one") } returns Response.success(HomeActivity(items = emptyList()))
        assertTrue(subject.list(HomeActivityKind.BuildFailures, "sample/one").isEmpty())
    }

    @Test fun `browser paths cannot switch origin or escape the selected project`() {
        for (path in listOf("https://evil.invalid/sample/one/tests/run", "//evil.invalid/sample/one/tests/run",
            "/other/project/tests/run", "/sample/one/../../outside", "/sample/one/%2e%2e/outside",
            "/sample/one/tests/run?token=unexpected", "/sample/one/tests/run#fragment")) {
            val error = runCatching { subject.dashboardUrl(path, "sample/one") }.exceptionOrNull()
            assertEquals(HomeActivityFailure.InvalidResponse, (error as HomeActivityException).failure)
        }
    }

    @Test fun `deployment base paths are retained even when named like the account`() {
        every { environment.serverUrl } returns "https://example.invalid:8443/sample/"
        assertEquals("https://example.invalid:8443/sample/sample/one/tests/test-cases/id",
            subject.dashboardUrl("/sample/one/tests/test-cases/id", "sample/one"))
    }
}
