package dev.tuist.app.ui.threads

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import dev.tuist.app.R
import dev.tuist.app.data.threads.*
import dev.tuist.app.ui.theme.TuistTheme

/** Explicit debug-only, network-free rendering of the production screens. */
class ThreadsPreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            TuistTheme(darkTheme = intent.getBooleanExtra("dark", false)) {
                var state by remember {
                    mutableStateOf(sampleState(intent.getStringExtra("screen")))
                }
                Scaffold(
                    bottomBar = {
                        NavigationBar {
                            NavigationBarItem(
                                false,
                                {},
                                icon = { Icon(painterResource(R.drawable.ic_device_mobile), null) },
                                label = { Text(stringResource(R.string.previews_title)) },
                            )
                            if (state.enabled)
                                NavigationBarItem(
                                    true,
                                    {},
                                    icon = { Icon(painterResource(R.drawable.ic_message), null) },
                                    label = { Text(stringResource(R.string.threads_title)) },
                                )
                            NavigationBarItem(
                                false,
                                {},
                                icon = { Icon(Icons.Default.Person, null) },
                                label = { Text(stringResource(R.string.profile_title)) },
                            )
                        }
                    }
                ) { padding ->
                    Surface(Modifier.fillMaxSize().padding(padding)) {
                        ThreadsContent(state) { action ->
                            state =
                                when (action) {
                                    is ThreadAction.Sheet -> state.copy(sheet = action.value)
                                    is ThreadAction.Draft -> state.copy(draft = action.value)
                                    is ThreadAction.Reply -> state.copy(reply = action.value)
                                    is ThreadAction.Open -> state.copy(selected = action.thread)
                                    is ThreadAction.Model ->
                                        state.copy(model = action.value, sheet = ThreadSheet.NEW)
                                    is ThreadAction.Repository ->
                                        state.copy(
                                            repository = action.value,
                                            sheet = ThreadSheet.NEW,
                                        )
                                    is ThreadAction.Archived ->
                                        state.copy(showArchived = action.value)
                                    is ThreadAction.Account ->
                                        state.copy(
                                            account = action.value,
                                            denied = false,
                                            threads = emptyList(),
                                        )
                                    ThreadAction.Back -> state.copy(selected = null)
                                    ThreadAction.Archive ->
                                        state.copy(
                                            selected =
                                                state.selected?.copy(archiveStatus = "archived")
                                        )
                                    ThreadAction.RetryModels ->
                                        state.copy(
                                            catalogError = false,
                                            models = listOf(sampleModel),
                                        )
                                    ThreadAction.PreviewShip ->
                                        state.copy(
                                            preview = samplePreview,
                                            sheet = ThreadSheet.SHIP,
                                        )
                                    ThreadAction.Create ->
                                        state.copy(
                                            selected = sampleThread.copy(goal = state.draft),
                                            sheet = null,
                                        )
                                    ThreadAction.DismissError -> state.copy(error = false)
                                    else -> state
                                }
                        }
                    }
                }
            }
        }
    }
}

private val sampleModel = ThreadModel("chatgpt", "sample-model", "Sample ChatGPT model")
private val sampleRepository = ThreadRepository("tuist/tuist", "main")
private val sampleThread =
    ServerThread(
        id = "sample-thread",
        title = "Make flaky tests easier to find",
        goal = "Add a flaky-test filter to the test results.",
        repository = "tuist/tuist",
        branch = "threads/flaky-test-filter",
        profile = "linux",
        provider = "chatgpt",
        model = "sample-model",
        status = "idle",
        visibility = "private",
        diff = "",
        archiveStatus = "active",
        revision = 1,
        messages =
            listOf(
                ThreadMessage(
                    "1",
                    "user",
                    "Add a flaky-test filter to the test results page.",
                    position = 1,
                ),
                ThreadMessage(
                    "2",
                    "tool",
                    "mix test test/tuist/test_runs_test.exs\n24 tests, 0 failures",
                    position = 2,
                    toolName = "bash",
                    toolStatus = "succeeded",
                ),
                ThreadMessage(
                    "3",
                    "assistant",
                    "The filter is ready. You can now switch between all results and flaky tests without losing your search.\n\nI added coverage for the filter and checked that existing results stay unchanged. All 24 focused tests passed.\n\nReview the changes when you are ready to ship.",
                    position = 3,
                    suggestions = listOf("Show the changes", "Check edge cases"),
                ),
            ),
    )
private val samplePreview =
    ShipPreview(
        headSha = "b270fc2c614aa7cd5321c728926bd2c2d915af81",
        baseSha = "9ae0a751bb36a7fb4b72541643bba3603a53782e",
        diff =
            "diff --git a/test_results.ex b/test_results.ex\n@@ -12,2 +12,3 @@\n   filters = [:all, :failed]\n+  filters = filters ++ [:flaky]\n   render_results(filters)",
        targetBranch = "threads/flaky-test-filter",
        mode = "branch",
        requestId = "sample-approval",
        threadId = "sample-thread",
        accountId = 1,
        repository = "tuist/tuist",
        sandboxId = "sample-sandbox",
        actor = "sample-user",
    )

private fun sampleState(screen: String?): ThreadsState {
    val base =
        ThreadsState(
            enabled = true,
            account = "tuist",
            accounts = listOf("tuist"),
            loading = false,
            threads =
                listOf(
                    sampleThread,
                    sampleThread.copy(
                        id = "second",
                        title = "Improve cache diagnostics",
                        goal = "Explain cache misses with actionable messages.",
                        messages = emptyList(),
                        status = "running",
                    ),
                ),
            models = listOf(sampleModel),
            repositories = listOf(sampleRepository),
            sample = true,
        )
    return when (screen) {
        "new" ->
            base.copy(
                sheet = ThreadSheet.NEW,
                draft = "Add a flaky-test filter to the test results page.",
                repository = sampleRepository,
            )
        "models" -> base.copy(sheet = ThreadSheet.MODELS)
        "error" ->
            base.copy(
                sheet = ThreadSheet.NEW,
                draft = "Add a flaky-test filter to the test results page.",
                repository = sampleRepository,
                models = emptyList(),
                catalogError = true,
            )
        "empty-models" -> base.copy(sheet = ThreadSheet.MODELS, models = emptyList())
        "loading" -> base.copy(sheet = ThreadSheet.NEW, models = emptyList(), catalogLoading = true)
        "conversation" -> base.copy(selected = sampleThread)
        "reconnecting" ->
            base.copy(selected = sampleThread.copy(status = "running"), reconnecting = true)
        "details" -> base.copy(selected = sampleThread, sheet = ThreadSheet.DETAILS)
        "ship" ->
            base.copy(selected = sampleThread, sheet = ThreadSheet.SHIP, preview = samplePreview)
        "archived" -> base.copy(selected = sampleThread.copy(archiveStatus = "archived"))
        "denied" ->
            base.copy(
                denied = true,
                accounts = listOf("sample-user", "tuist"),
                threads = emptyList(),
            )
        "flag-off" -> base.copy(enabled = false)
        else -> base
    }
}
