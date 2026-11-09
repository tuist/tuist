package dev.tuist.app.ui.jams

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
import dev.tuist.app.data.jams.*
import dev.tuist.app.ui.theme.TuistTheme

/** Explicit debug-only, network-free rendering of the production screens. */
class JamsPreviewActivity : ComponentActivity() {
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
                        JamsContent(state) { action ->
                            state =
                                when (action) {
                                    is JamAction.Sheet -> state.copy(sheet = action.value)
                                    is JamAction.Draft -> state.copy(draft = action.value)
                                    is JamAction.Reply -> state.copy(reply = action.value)
                                    is JamAction.Open -> state.copy(selected = action.jam)
                                    is JamAction.Model ->
                                        state.copy(model = action.value, sheet = JamSheet.NEW)
                                    is JamAction.Repository ->
                                        state.copy(
                                            repository = action.value,
                                            sheet = JamSheet.NEW,
                                        )
                                    is JamAction.Archived ->
                                        state.copy(showArchived = action.value)
                                    JamAction.Back -> state.copy(selected = null)
                                    JamAction.Archive ->
                                        state.copy(
                                            selected =
                                                state.selected?.copy(archiveStatus = "archived")
                                        )
                                    JamAction.RetryModels ->
                                        state.copy(
                                            catalogError = false,
                                            models = listOf(sampleModel),
                                        )
                                    JamAction.PreviewShip ->
                                        state.copy(
                                            preview = samplePreview,
                                            sheet = JamSheet.SHIP,
                                        )
                                    JamAction.Create ->
                                        state.copy(
                                            selected = sampleJam.copy(goal = state.draft),
                                            sheet = null,
                                        )
                                    JamAction.DismissError -> state.copy(error = false)
                                    else -> state
                                }
                        }
                    }
                }
            }
        }
    }
}

private val sampleModel = JamModel("chatgpt", "sample-model", "Sample ChatGPT model")
private val sampleRepository = JamRepository("tuist/tuist", "main")
private val sampleJam =
    ServerJam(
        id = "sample-jam",
        title = "Make flaky tests easier to find",
        goal = "Add a flaky-test filter to the test results.",
        repository = "tuist/tuist",
        branch = "jams/flaky-test-filter",
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
                JamMessage(
                    "1",
                    "user",
                    "Add a flaky-test filter to the test results page.",
                    position = 1,
                ),
                JamMessage(
                    "2",
                    "tool",
                    "mix test test/tuist/test_runs_test.exs\n24 tests, 0 failures",
                    position = 2,
                    toolName = "bash",
                    toolStatus = "succeeded",
                ),
                JamMessage(
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
        targetBranch = "jams/flaky-test-filter",
        mode = "branch",
        requestId = "sample-approval",
        jamId = "sample-jam",
        accountId = 1,
        repository = "tuist/tuist",
        sandboxId = "sample-sandbox",
        actor = "sample-user",
    )

private fun sampleState(screen: String?): JamsState {
    val base =
        JamsState(
            enabled = true,
            account = "tuist",
            loading = false,
            jams =
                listOf(
                    sampleJam,
                    sampleJam.copy(
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
        "empty" -> base.copy(jams = emptyList())
        "new" ->
            base.copy(
                sheet = JamSheet.NEW,
                draft = "Add a flaky-test filter to the test results page.",
                repository = sampleRepository,
            )
        "models" -> base.copy(sheet = JamSheet.MODELS)
        "error" ->
            base.copy(
                sheet = JamSheet.NEW,
                draft = "Add a flaky-test filter to the test results page.",
                repository = sampleRepository,
                models = emptyList(),
                catalogError = true,
            )
        "empty-models" -> base.copy(sheet = JamSheet.MODELS, models = emptyList())
        "loading" -> base.copy(sheet = JamSheet.NEW, models = emptyList(), catalogLoading = true)
        "conversation" -> base.copy(selected = sampleJam)
        "interrupted" -> base.copy(selected = sampleJam.copy(status = "interrupted"))
        "outcome-unknown" -> base.copy(selected = sampleJam.copy(status = "outcome_unknown"))
        "reconnecting" ->
            base.copy(selected = sampleJam.copy(status = "running"), reconnecting = true)
        "details" -> base.copy(selected = sampleJam, sheet = JamSheet.DETAILS)
        "ship" ->
            base.copy(selected = sampleJam, sheet = JamSheet.SHIP, preview = samplePreview)
        "archived" -> base.copy(selected = sampleJam.copy(archiveStatus = "archived"))
        "denied" ->
            base.copy(
                denied = true,
                jams = emptyList(),
            )
        "flag-off" -> base.copy(enabled = false)
        else -> base
    }
}
