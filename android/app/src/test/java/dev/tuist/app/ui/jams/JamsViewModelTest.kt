package dev.tuist.app.ui.jams

import androidx.lifecycle.ViewModelStore
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.featureflags.FeatureFlag
import dev.tuist.app.data.featureflags.FeatureFlagsRepository
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.jams.*
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

@OptIn(ExperimentalCoroutinesApi::class)
class JamsViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val auth = mockk<AuthRepository>()
    private val flags = mockk<FeatureFlagsRepository>()
    private val transport = mockk<JamTransport>()
    private val api = mockk<JamsApi>()
    private val watcher = mockk<JamWatcher>()
    private val authState =
        MutableStateFlow<AuthState>(AuthState.LoggedIn(Account("alice@example.com", "alice")))
    private val enabled = MutableStateFlow<Set<FeatureFlag>>(emptySet())
    private val session = MutableStateFlow(dev.tuist.app.data.auth.TokenStorage.Session("alice-login", 0))
    private val store = ViewModelStore()
    private val model = JamModel("chatgpt", "chosen-model", "Chosen model")
    private val jam =
        ServerJam(
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
        every { auth.session } returns session
        every { flags.enabled } returns enabled
        every { transport.api } returns api
        coEvery { api.list(any(), any()) } returns JamPage(listOf(jam))
        coEvery { api.history(any(), any(), any()) } returns jam
        coEvery { api.repositories(any()) } returns JamRepositories(emptyList())
        coEvery { api.models(any()) } returns JamModelCatalog(listOf(model), emptyList())
    }

    @After
    fun tearDown() {
        store.clear()
        Dispatchers.resetMain()
    }

    private fun viewModel() =
        JamsViewModel(transport, auth, flags, watcher).also {
            store.put("jams", it)
        }

    @Test fun `jams use personal account despite legacy organization selection`() = runTest(dispatcher) {
        enabled.value = setOf(FeatureFlag.AI)
        session.value = session.value.copy(organization = "organization-one")
        val vm = viewModel()
        runCurrent()
        assertEquals("alice", vm.state.value.account)
        coVerify { api.list("alice", null) }
        session.value = session.value.copy(generation = 1, organization = "organization-two")
        runCurrent()
        assertEquals("alice", vm.state.value.account)
        coVerify(exactly = 0) { api.list("organization-one", null) }
        coVerify(exactly = 0) { api.list("organization-two", null) }
        assertEquals("alice", (authState.value as AuthState.LoggedIn).account.handle)
    }

    @Test
    fun `disjoint inbox refresh restarts pagination and load more reaches every jam`() =
        runTest(dispatcher) {
            val old = (1..25).map { jam.copy(id = "old-$it") }
            val new = (1..30).map { jam.copy(id = "new-$it") }
            coEvery { api.list("alice", null) } returns JamPage(old)
            enabled.value = setOf(FeatureFlag.AI)
            val vm = viewModel()
            runCurrent()
            coEvery { api.list("alice", null) } returns JamPage(new.take(25), "fresh")
            coEvery { api.list("alice", "fresh") } returns
                JamPage(new.drop(25) + old.take(20), "tail")
            coEvery { api.list("alice", "tail") } returns JamPage(old.drop(20))

            vm.refresh(quiet = false)
            assertEquals(new.take(25), vm.state.value.jams)
            assertEquals("fresh", vm.state.value.cursor)
            vm.loadMore()
            runCurrent()
            vm.loadMore()
            runCurrent()
            assertEquals(new + old, vm.state.value.jams)
            assertNull(vm.state.value.cursor)
        }

    @Test
    fun `contiguous inbox refresh preserves loaded tail and its cursor`() =
        runTest(dispatcher) {
            val old = (1..50).map { jam.copy(id = "old-$it") }
            val new = jam.copy(id = "new")
            enabled.value = setOf(FeatureFlag.AI)
            for (cursor in listOf(null, "older")) {
                coEvery { api.list("alice", null) } returns JamPage(old.take(25), "second")
                coEvery { api.list("alice", "second") } returns JamPage(old.drop(25), cursor)
                val vm = viewModel()
                runCurrent()
                vm.loadMore()
                runCurrent()
                coEvery { api.list("alice", null) } returns
                    JamPage(listOf(new) + old.take(24), "fresh")
                vm.refresh(quiet = false)
                assertEquals(listOf(new) + old, vm.state.value.jams)
                assertEquals(cursor, vm.state.value.cursor)
                val reordered = listOf(old[1].copy(revision = 2), new, old[0]) + old.drop(2)
                coEvery { api.list("alice", null) } returns
                    JamPage(reordered.take(25), "fresh")
                vm.refresh(quiet = false)
                assertEquals(reordered, vm.state.value.jams)
                assertEquals(cursor, vm.state.value.cursor)
            }
        }

    @Test
    fun `moved overlap and changed boundary do not prove inbox continuity`() =
        runTest(dispatcher) {
            val old = (1..25).map { jam.copy(id = "old-$it") }
            val new = (1..24).map { jam.copy(id = "new-$it") }
            enabled.value = setOf(FeatureFlag.AI)
            val pages =
                listOf(
                    new + old.last().copy(revision = 2),
                    new + old.first().copy(revision = 2),
                    new + old.last(),
                    emptyList(),
                )
            for (fresh in pages) {
                coEvery { api.list("alice", null) } returns JamPage(old, "old-cursor")
                val vm = viewModel()
                runCurrent()
                coEvery { api.list("alice", null) } returns
                    JamPage(fresh, if (fresh.isEmpty()) null else "fresh")
                vm.refresh(quiet = false)
                assertEquals(fresh, vm.state.value.jams)
                assertEquals(if (fresh.isEmpty()) null else "fresh", vm.state.value.cursor)
            }
        }

    @Test
    fun `flag off performs no requests and revocation discards private state`() =
        runTest(dispatcher) {
            val vm = viewModel()
            runCurrent()
            coVerify(exactly = 0) { api.list(any(), any()) }
            enabled.value = setOf(FeatureFlag.AI)
            runCurrent()
            assertEquals(1, vm.state.value.jams.size)
            vm.draft("Private draft")
            enabled.value = emptySet()
            runCurrent()
            assertFalse(vm.state.value.enabled)
            assertTrue(vm.state.value.jams.isEmpty())
            assertEquals("", vm.state.value.draft)
        }

    @Test
    fun `creation requires an available explicit model and retries with the same request identity`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val vm = viewModel()
            runCurrent()
            vm.sheet(JamSheet.NEW)
            runCurrent()
            vm.draft("Build something")
            vm.create()
            runCurrent()
            coVerify(exactly = 0) { api.create(any(), any()) }
            vm.model(model)
            val requests = mutableListOf<CreateJam>()
            coEvery { api.create("alice", capture(requests)) } throws
                IOException("Offline") andThen
                jam
            vm.create()
            runCurrent()
            assertEquals("Build something", vm.state.value.draft)
            vm.dismissError()
            vm.create()
            runCurrent()
            assertEquals(requests[0], requests[1])
            assertEquals("chosen-model", requests[0].model)
            assertEquals("id", vm.state.value.selected?.id)
            assertEquals(1, vm.state.value.jams.count { it.id == "id" })
            assertFalse(vm.state.value.error)
        }

    @Test
    fun `an old account response cannot replace the current account inbox`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val pending = CompletableDeferred<JamPage>()
            coEvery { api.list("alice", any()) } coAnswers { pending.await() }
            val vm = viewModel()
            runCurrent()
            authState.value = AuthState.LoggedIn(Account("bob@example.com", "bob"))
            coEvery { api.list("bob", any()) } returns JamPage(emptyList())
            runCurrent()
            pending.complete(JamPage(listOf(jam)))
            runCurrent()
            assertEquals("bob", vm.state.value.account)
            assertTrue(vm.state.value.jams.isEmpty())
        }

    @Test
    fun `denied jams stay scoped to the login until the global profile changes`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val vm = viewModel()
            runCurrent()
            vm.draft("Private draft")
            coEvery { api.list("alice", any()) } throws
                retrofit2.HttpException(Response.error<JamPage>(403, "".toResponseBody()))
            vm.refresh(quiet = false)
            assertTrue(vm.state.value.denied)
            assertEquals("alice", vm.state.value.account)
            assertTrue(vm.state.value.jams.isEmpty())
            assertEquals("", vm.state.value.draft)
            coEvery { api.list("bob", any()) } returns JamPage(emptyList())
            authState.value = AuthState.LoggedIn(Account("bob@example.com", "bob"))
            runCurrent()
            assertFalse(vm.state.value.denied)
            assertEquals("bob", vm.state.value.account)
            assertTrue(vm.state.value.jams.isEmpty())
        }

    @Test
    fun `refresh retains earlier history and rejects a stale revision`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val vm = viewModel()
            runCurrent()
            val recent =
                jam.copy(
                    revision = 5,
                    hasMore = true,
                    nextBefore = 8,
                    messages = listOf(JamMessage("recent", "assistant", "Recent", position = 8)),
                )
            coEvery { api.history("alice", "id", null) } returns recent
            vm.open(jam)
            runCurrent()
            coEvery { api.history("alice", "id", 8) } returns
                recent.copy(
                    hasMore = false,
                    nextBefore = null,
                    messages = listOf(JamMessage("earlier", "user", "Earlier", position = 2)),
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
                        recent.messages + JamMessage("new", "assistant", "New", position = 10),
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
                    jam.copy(
                        hasMore = hadMore,
                        nextBefore = if (hadMore) 1 else null,
                        messages =
                            listOf(
                                JamMessage("1", "user", "First", position = 1),
                                JamMessage("2", "assistant", "Second", position = 2),
                            ),
                    )
                coEvery { api.history("alice", "id", null) } returns cached
                val vm = viewModel()
                runCurrent()
                vm.open(cached)
                runCurrent()
                val fresh =
                    jam.copy(
                        revision = 101,
                        hasMore = true,
                        nextBefore = 100,
                        messages =
                            listOf(
                                JamMessage("100", "user", "Latest request", position = 100),
                                JamMessage("101", "assistant", "Latest reply", position = 101),
                            ),
                    )
                coEvery { api.history("alice", "id", null) } returns fresh
                vm.refresh(quiet = false)
                assertEquals(fresh, vm.state.value.selected)
                coEvery { api.history("alice", "id", 100) } returns
                    fresh.copy(
                        nextBefore = 3,
                        messages =
                            listOf(JamMessage("3", "user", "Missing request", position = 3)),
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
    fun `an interrupted jam accepts a follow-up but active uncertain and archived jams do not`() =
        runTest(dispatcher) {
            enabled.value = setOf(FeatureFlag.AI)
            val interrupted = jam.copy(status = "interrupted")
            val blocked =
                listOf("queued", "running", "compacting", "shipping", "outcome_unknown").map {
                    jam.copy(status = it)
                } + interrupted.copy(archiveStatus = "archived")
            val requests = mutableListOf<SendMessage>()
            val accepted =
                jam.copy(
                    revision = 2,
                    messages = listOf(JamMessage("follow-up", "user", "Continue", position = 2)),
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
                        JamPage(listOf(jam.copy(title = "Updated remotely", revision = 9)))
                    arg<suspend () -> Unit>(2).invoke()
                    assertEquals("Updated remotely", vm.state.value.jams.first().title)
                    coEvery { api.list("alice", any()) } throws
                        retrofit2.HttpException(
                            Response.error<JamPage>(403, "".toResponseBody())
                        )
                    arg<suspend () -> Unit>(3).invoke()
                }
            vm.watch()
            assertTrue(vm.state.value.denied)
            assertTrue(vm.state.value.jams.isEmpty())
            coVerify(exactly = 0) { api.send(any(), any(), any()) }
            coVerify(exactly = 0) { api.ship(any(), any(), any()) }
        }
}
