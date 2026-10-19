package dev.tuist.app.ui.home

import dev.tuist.app.data.home.HomeActivityException
import dev.tuist.app.data.home.HomeActivityFailure
import dev.tuist.app.data.home.HomeActivityItem
import dev.tuist.app.data.home.HomeActivityKind
import dev.tuist.app.data.home.HomeActivityRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HomeActivityViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val repository = mockk<HomeActivityRepository>()

    @Before fun setUp() { Dispatchers.setMain(dispatcher) }
    @After fun tearDown() { Dispatchers.resetMain() }

    @Test fun `loads three bounded sections independently`() = runTest(dispatcher) {
        val flakes = CompletableDeferred<List<HomeActivityItem>>()
        coEvery { repository.list(any(), "sample/one") } returns (1..5).map { item("row-$it") }
        coEvery { repository.list(HomeActivityKind.FlakyTests, "sample/one") } coAnswers { flakes.await() }
        val subject = HomeActivityViewModel(repository)

        subject.selectProject("sample/one")
        advanceUntilIdle()
        assertEquals(3, subject.uiState.value.sections[HomeActivityKind.BuildFailures]?.items?.size)
        assertTrue(subject.uiState.value.sections[HomeActivityKind.FlakyTests]!!.isLoading)

        flakes.complete(emptyList())
        advanceUntilIdle()
        assertTrue(subject.uiState.value.sections[HomeActivityKind.FlakyTests]!!.hasLoaded)
        assertFalse(subject.uiState.value.sections[HomeActivityKind.FlakyTests]!!.isLoading)
    }

    @Test fun `a section error does not become an empty success or hide siblings`() = runTest(dispatcher) {
        coEvery { repository.list(any(), "sample/one") } returns listOf(item("success"))
        coEvery { repository.list(HomeActivityKind.FlakyTests, "sample/one") } throws HomeActivityException(HomeActivityFailure.Unsupported)
        val subject = HomeActivityViewModel(repository)
        subject.selectProject("sample/one")
        advanceUntilIdle()

        assertEquals("success", subject.uiState.value.sections[HomeActivityKind.BuildFailures]!!.items.first().id)
        assertEquals(HomeActivityFailure.Unsupported, subject.uiState.value.sections[HomeActivityKind.FlakyTests]!!.error)
        assertFalse(subject.uiState.value.sections[HomeActivityKind.FlakyTests]!!.hasLoaded)
    }

    @Test fun `project switching clears old content immediately and ignores late requests`() = runTest(dispatcher) {
        val old = CompletableDeferred<List<HomeActivityItem>>()
        coEvery { repository.list(any(), "sample/one") } coAnswers { withContext(NonCancellable) { old.await() } }
        coEvery { repository.list(any(), "sample/two") } returns listOf(item("new"))
        val subject = HomeActivityViewModel(repository)
        subject.selectProject("sample/one")
        advanceUntilIdle()
        subject.selectProject("sample/two")
        assertEquals("sample/two", subject.uiState.value.fullHandle)
        assertTrue(subject.uiState.value.sections.values.all { it.items.isEmpty() })
        advanceUntilIdle()
        old.complete(listOf(item("old")))
        advanceUntilIdle()

        assertTrue(subject.uiState.value.sections.values.all { it.items.map { row -> row.id } == listOf("new") })
    }

    @Test fun `refresh failures preserve rows and retry only requests the failed section`() = runTest(dispatcher) {
        coEvery { repository.list(any(), "sample/one") } returns listOf(item("first"))
        val subject = HomeActivityViewModel(repository)
        subject.selectProject("sample/one")
        advanceUntilIdle()
        coEvery { repository.list(HomeActivityKind.BuildFailures, "sample/one") } throws HomeActivityException(HomeActivityFailure.Unavailable)

        subject.refresh()
        assertTrue(subject.uiState.value.isRefreshing)
        assertEquals("first", subject.uiState.value.sections[HomeActivityKind.BuildFailures]!!.items.first().id)
        advanceUntilIdle()
        assertEquals("first", subject.uiState.value.sections[HomeActivityKind.BuildFailures]!!.items.first().id)
        assertEquals(HomeActivityFailure.Unavailable, subject.uiState.value.sections[HomeActivityKind.BuildFailures]!!.error)
        assertFalse(subject.uiState.value.isRefreshing)

        coEvery { repository.list(HomeActivityKind.BuildFailures, "sample/one") } returns listOf(item("retried"))
        subject.retry(HomeActivityKind.BuildFailures)
        subject.retry(HomeActivityKind.BuildFailures)
        advanceUntilIdle()
        assertEquals("retried", subject.uiState.value.sections[HomeActivityKind.BuildFailures]!!.items.first().id)
        assertNull(subject.uiState.value.sections[HomeActivityKind.BuildFailures]!!.error)
        coVerify(exactly = 3) { repository.list(HomeActivityKind.BuildFailures, "sample/one") }
        coVerify(exactly = 2) { repository.list(HomeActivityKind.TestFailures, "sample/one") }
    }

    @Test fun `clearing the project removes activity and a same-project return does not reload`() = runTest(dispatcher) {
        coEvery { repository.list(any(), "sample/one") } returns emptyList()
        val subject = HomeActivityViewModel(repository)
        subject.selectProject("sample/one")
        advanceUntilIdle()
        subject.selectProject("sample/one")
        advanceUntilIdle()
        coVerify(exactly = 3) { repository.list(any(), "sample/one") }
        subject.selectProject(null)
        assertNull(subject.uiState.value.fullHandle)
        assertTrue(subject.uiState.value.sections.isEmpty())
    }

    private fun item(id: String) = HomeActivityItem(id, "AppTests", "main", 1_700_000_000L,
        "https://example.invalid/sample/one/tests/test-runs/$id")
}
