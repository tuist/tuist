package dev.tuist.app.ui.threads

import androidx.lifecycle.ViewModelStore
import dev.tuist.app.api.OrganizationsApi
import dev.tuist.app.api.model.OrganizationList1
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.featureflags.FeatureFlag
import dev.tuist.app.data.featureflags.FeatureFlagsRepository
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.threads.*
import io.mockk.*
import java.io.IOException
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import retrofit2.Response
import retrofit2.Retrofit

@OptIn(ExperimentalCoroutinesApi::class)
class ThreadsViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val auth = mockk<AuthRepository>()
    private val flags = mockk<FeatureFlagsRepository>()
    private val transport = mockk<ThreadTransport>()
    private val api = mockk<ThreadsApi>()
    private val watcher = mockk<ThreadWatcher>()
    private val retrofit = mockk<Retrofit>()
    private val organizations = mockk<OrganizationsApi>()
    private val authState =
        MutableStateFlow<AuthState>(AuthState.LoggedIn(Account("alice@example.com", "alice")))
    private val enabled = MutableStateFlow<Set<FeatureFlag>>(emptySet())
    private val store = ViewModelStore()
    private val model = ThreadModel("chatgpt", "chosen-model", "Chosen model")
    private val thread =
        ServerThread(
            "id",
            "Title",
            "Goal",
            "",
            "",
            "linux",
            "chatgpt",
            "chosen-model",
            "idle",
            "private",
            emptyList(),
            "",
            revision = 1,
            archiveStatus = "active",
        )

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        every { auth.authState } returns authState
        every { flags.enabled } returns enabled
        every { transport.api } returns api
        every { retrofit.create(OrganizationsApi::class.java) } returns organizations
        coEvery { organizations.listOrganizations() } returns
            Response.success(OrganizationList1(emptyList()))
        coEvery { api.list(any(), any()) } returns ThreadPage(listOf(thread))
        coEvery { api.history(any(), any(), any()) } returns thread
        coEvery { api.repositories(any()) } returns ThreadRepositories(emptyList())
        coEvery { api.models(any()) } returns ThreadModelCatalog(listOf(model), emptyList())
    }

    @After
    fun tearDown() {
        store.clear()
        Dispatchers.resetMain()
    }

    private fun viewModel() =
        ThreadsViewModel(transport, auth, flags, retrofit, watcher).also {
            store.put("threads", it)
        }

    @Test
    fun `flag off performs no requests and revocation discards private state`() =
        runTest(dispatcher) {
            val vm = viewModel()
            runCurrent()
            coVerify(exactly = 0) { api.list(any(), any()) }
            enabled.value = setOf(FeatureFlag.AI)
            runCurrent()
            assertEquals(1, vm.state.value.threads.size)
            vm.draft("Private draft")
            enabled.value = emptySet()
            runCurrent()
            assertFalse(vm.state.value.enabled)
            assertTrue(vm.state.value.threads.isEmpty())
            assertEquals("", vm.state.value.draft)
        }

    @Test
    fun `creation requires an available explicit model and retries with the same request identity`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val vm = viewModel()
            runCurrent()
            vm.sheet(ThreadSheet.NEW)
            runCurrent()
            vm.draft("Build something")
            vm.create()
            runCurrent()
            coVerify(exactly = 0) { api.create(any(), any()) }
            vm.model(model)
            val requests = mutableListOf<CreateThread>()
            coEvery { api.create("alice", capture(requests)) } throws
                IOException("Offline") andThen
                thread
            vm.create()
            runCurrent()
            assertEquals("Build something", vm.state.value.draft)
            vm.dismissError()
            vm.create()
            runCurrent()
            assertEquals(requests[0], requests[1])
            assertEquals("chosen-model", requests[0].model)
            assertEquals("id", vm.state.value.selected?.id)
            assertEquals(1, vm.state.value.threads.count { it.id == "id" })
            assertFalse(vm.state.value.error)
        }

    @Test
    fun `an old account response cannot replace the current account inbox`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val pending = CompletableDeferred<ThreadPage>()
            coEvery { api.list("alice", any()) } coAnswers { pending.await() }
            val vm = viewModel()
            runCurrent()
            authState.value = AuthState.LoggedIn(Account("bob@example.com", "bob"))
            coEvery { api.list("bob", any()) } returns ThreadPage(emptyList())
            runCurrent()
            pending.complete(ThreadPage(listOf(thread)))
            runCurrent()
            assertEquals("bob", vm.state.value.account)
            assertTrue(vm.state.value.threads.isEmpty())
        }

    @Test
    fun `a denied organization can return to the personal account without retaining its data`() =
        runTest(dispatcher) {
            coEvery { organizations.listOrganizations() } returns
                Response.success(OrganizationList1(listOf(mockk { every { name } returns "team" })))
            coEvery { api.list("team", any()) } throws
                retrofit2.HttpException(Response.error<ThreadPage>(403, "".toResponseBody()))
            enabled.value = setOf(FeatureFlag.AI)
            val vm = viewModel()
            runCurrent()
            vm.draft("Private draft")
            vm.selectAccount("team")
            runCurrent()
            assertTrue(vm.state.value.denied)
            assertTrue(vm.state.value.threads.isEmpty())
            assertEquals("", vm.state.value.draft)
            coEvery { api.list("alice", any()) } returns ThreadPage(emptyList())
            vm.selectAccount("alice")
            runCurrent()
            assertFalse(vm.state.value.denied)
            assertEquals("alice", vm.state.value.account)
            assertTrue(vm.state.value.threads.isEmpty())
        }

    @Test
    fun `refresh retains earlier history and rejects a stale revision`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val vm = viewModel()
            runCurrent()
            val recent =
                thread.copy(
                    revision = 5,
                    hasMore = true,
                    nextBefore = 8,
                    messages = listOf(ThreadMessage("recent", "assistant", "Recent", position = 8)),
                )
            coEvery { api.history("alice", "id", null) } returns recent
            vm.open(thread)
            runCurrent()
            coEvery { api.history("alice", "id", 8) } returns
                recent.copy(
                    hasMore = false,
                    nextBefore = null,
                    messages = listOf(ThreadMessage("earlier", "user", "Earlier", position = 2)),
                )
            vm.loadMore()
            runCurrent()
            coEvery { api.history("alice", "id", null) } returns recent.copy(revision = 4)
            vm.refresh(quiet = false)
            assertEquals(
                listOf("earlier", "recent"),
                vm.state.value.selected?.messages?.map { it.id },
            )
            assertEquals(false, vm.state.value.selected?.hasMore)
            assertEquals(5, vm.state.value.selected?.revision)
            coEvery { api.history("alice", "id", null) } returns
                recent.copy(
                    revision = 6,
                    messages =
                        recent.messages + ThreadMessage("new", "assistant", "New", position = 10),
                )
            vm.refresh(quiet = false)
            assertEquals(
                listOf("earlier", "recent", "new"),
                vm.state.value.selected?.messages?.map { it.id },
            )
            assertEquals(false, vm.state.value.selected?.hasMore)
            assertNull(vm.state.value.selected?.nextBefore)
        }

    @Test
    fun `reconnect resets disjoint history so missing messages remain reachable`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            for (hadMore in listOf(false, true)) {
                val cached =
                    thread.copy(
                        hasMore = hadMore,
                        nextBefore = if (hadMore) 1 else null,
                        messages =
                            listOf(
                                ThreadMessage("1", "user", "First", position = 1),
                                ThreadMessage("2", "assistant", "Second", position = 2),
                            ),
                    )
                coEvery { api.history("alice", "id", null) } returns cached
                val vm = viewModel()
                runCurrent()
                vm.open(cached)
                runCurrent()
                val fresh =
                    thread.copy(
                        revision = 101,
                        hasMore = true,
                        nextBefore = 100,
                        messages =
                            listOf(
                                ThreadMessage("100", "user", "Latest request", position = 100),
                                ThreadMessage("101", "assistant", "Latest reply", position = 101),
                            ),
                    )
                coEvery { api.history("alice", "id", null) } returns fresh
                vm.refresh(quiet = false)
                assertEquals(fresh, vm.state.value.selected)
                coEvery { api.history("alice", "id", 100) } returns
                    fresh.copy(
                        nextBefore = 3,
                        messages =
                            listOf(ThreadMessage("3", "user", "Missing request", position = 3)),
                    )
                vm.loadMore()
                runCurrent()
                assertEquals(
                    listOf("3", "100", "101"),
                    vm.state.value.selected?.messages?.map { it.id },
                )
                assertEquals(3, vm.state.value.selected?.nextBefore)
            }
        }

    @Test
    fun `an interrupted thread accepts a follow-up but active uncertain and archived threads do not`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val interrupted = thread.copy(status = "interrupted")
            val blocked =
                listOf("queued", "running", "compacting", "shipping", "outcome_unknown").map {
                    thread.copy(status = it)
                } + interrupted.copy(archiveStatus = "archived")
            val requests = mutableListOf<SendMessage>()
            val accepted =
                thread.copy(
                    revision = 2,
                    messages = listOf(ThreadMessage("follow-up", "user", "Continue", position = 2)),
                )
            coEvery { api.send("alice", "id", capture(requests)) } coAnswers
                {
                    coEvery { api.history("alice", "id", null) } returns accepted
                    accepted
                }
            for (candidate in blocked + interrupted) {
                coEvery { api.history("alice", "id", null) } returns candidate
                val vm = viewModel()
                runCurrent()
                vm.open(candidate)
                runCurrent()
                vm.reply("Continue")
                assertEquals(candidate == interrupted, candidate.canMessage())
                vm.send()
                runCurrent()
                if (candidate == interrupted) {
                    assertEquals("Continue", vm.state.value.selected?.messages?.last()?.content)
                    assertEquals("", vm.state.value.reply)
                } else {
                    assertEquals("Continue", vm.state.value.reply)
                    assertTrue(requests.isEmpty())
                }
            }
            assertEquals(listOf("Continue"), requests.map { it.content })
        }

    @Test
    fun `channel reconnection refetches state and revocation clears cached conversations without replaying writes`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val vm = viewModel()
            runCurrent()
            coEvery { watcher.watch("alice", null, any(), any()) } coAnswers
                {
                    coEvery { api.list("alice", any()) } returns
                        ThreadPage(listOf(thread.copy(title = "Updated remotely", revision = 9)))
                    arg<suspend () -> Unit>(2).invoke()
                    assertEquals("Updated remotely", vm.state.value.threads.first().title)
                    coEvery { api.list("alice", any()) } throws
                        retrofit2.HttpException(
                            Response.error<ThreadPage>(403, "".toResponseBody())
                        )
                    arg<suspend () -> Unit>(3).invoke()
                }
            vm.watch()
            assertTrue(vm.state.value.denied)
            assertTrue(vm.state.value.threads.isEmpty())
            coVerify(exactly = 0) { api.send(any(), any(), any()) }
            coVerify(exactly = 0) { api.ship(any(), any(), any()) }
        }
}
