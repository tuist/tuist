package dev.tuist.app.ui.jams

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.featureflags.FeatureFlag
import dev.tuist.app.data.featureflags.FeatureFlagsRepository
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.jams.*
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import retrofit2.HttpException

enum class JamSheet {
    NEW,
    MODELS,
    REPOSITORIES,
    DETAILS,
    SHIP,
}

data class JamsState(
    val enabled: Boolean = false,
    val account: String = "",
    val jams: List<ServerJam> = emptyList(),
    val selected: ServerJam? = null,
    val cursor: String? = null,
    val loading: Boolean = true,
    val busy: Boolean = false,
    val error: Boolean = false,
    val denied: Boolean = false,
    val reconnecting: Boolean = false,
    val sheet: JamSheet? = null,
    val draft: String = "",
    val reply: String = "",
    val repository: JamRepository? = null,
    val repositories: List<JamRepository> = emptyList(),
    val model: JamModel? = null,
    val models: List<JamModel> = emptyList(),
    val modelErrors: List<JamModelError> = emptyList(),
    val catalogLoading: Boolean = false,
    val catalogError: Boolean = false,
    val repositoryError: Boolean = false,
    val preview: ShipPreview? = null,
    val showArchived: Boolean = false,
    val sample: Boolean = false,
)

@HiltViewModel
class JamsViewModel
@Inject
constructor(
    transport: JamTransport,
    auth: AuthRepository,
    flags: FeatureFlagsRepository,
    private val watcher: JamWatcher,
) : ViewModel() {
    private val api = transport.api
    private val _state = MutableStateFlow(JamsState())
    val state = _state.asStateFlow()
    private var generation = 0
    private var mutation: Job? = null
    private var catalog: Job? = null
    private var createRequest: CreateJam? = null
    private var messageRequest: Pair<String, SendMessage>? = null

    init {
        viewModelScope.launch {
            combine(auth.authState, auth.session, flags.enabled) { state, _, enabled ->
                    (state as? AuthState.LoggedIn)?.account?.handle to (FeatureFlag.AI in enabled)
                }
                .distinctUntilChanged()
                .collect { (account, enabled) ->
                    generation++
                    mutation?.cancel()
                    catalog?.cancel()
                    createRequest = null
                    messageRequest = null
                    _state.value =
                        JamsState(
                            enabled = account != null && enabled,
                            account = account.orEmpty(),
                        )
                    if (account != null && enabled) {
                        refresh()
                    }
                }
        }
    }

    suspend fun refresh(quiet: Boolean = false) {
        val old = _state.value
        if (!old.enabled || old.busy || old.denied) return
        val fence = generation
        try {
            val page = api.list(old.account)
            val selected = old.selected?.let { api.history(old.account, it.id) }
            if (fence != generation) return
            _state.update { current ->
                val boundary = page.jams.lastOrNull()
                val boundaryIndex = current.jams.indexOfFirst { it.id == boundary?.id }
                val incoming = page.jams.map { it.id }.toSet()
                // A moved overlap alone does not prove that the two recency windows meet.
                val contiguous =
                    boundaryIndex >= 0 &&
                        boundary?.revision != null &&
                        boundary == current.jams[boundaryIndex] &&
                        current.jams.take(boundaryIndex + 1).all { it.id in incoming }
                current.copy(
                    jams =
                        (page.jams.map { fresh ->
                                val existing = current.jams.find { it.id == fresh.id }
                                if ((existing?.revision ?: 0) > (fresh.revision ?: 0)) existing!!
                                else fresh
                            } + if (contiguous) current.jams else emptyList())
                            .distinctBy { it.id },
                    cursor = if (contiguous) current.cursor else page.nextCursor,
                    selected =
                        if (current.selected?.id == selected?.id) merge(current.selected, selected)
                        else current.selected,
                    loading = false,
                    error = if (quiet) current.error else false,
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (fence == generation) failure(e, quiet)
        }
    }

    fun refresh() {
        viewModelScope.launch { refresh(quiet = false) }
    }

    suspend fun watch() {
        val current = _state.value
        if (!current.enabled || current.denied) return
        val fence = generation
        if (current.sheet == JamSheet.NEW || current.sheet == JamSheet.MODELS) loadCatalog()
        watcher.watch(
            current.account,
            current.selected?.id,
            invalidate = {
                if (fence == generation) {
                    _state.update { it.copy(reconnecting = false) }
                    refresh(quiet = false)
                }
            },
            disconnected = {
                if (fence == generation) {
                    _state.update { it.copy(reconnecting = true) }
                    refresh(quiet = true)
                }
            },
        )
    }

    fun open(jam: ServerJam) {
        _state.update { it.copy(selected = jam, reply = "", error = false) }
        viewModelScope.launch { refresh(quiet = false) }
    }

    fun back() {
        if (!_state.value.busy) _state.update { it.copy(selected = null, sheet = null, reply = "") }
    }

    fun draft(value: String) {
        _state.update { it.copy(draft = value) }
    }

    fun reply(value: String) {
        _state.update { it.copy(reply = value) }
    }

    fun archived(value: Boolean) {
        _state.update { it.copy(showArchived = value) }
    }

    fun dismissError() {
        _state.update { it.copy(error = false) }
    }

    fun sheet(value: JamSheet?) {
        if (_state.value.busy) return
        _state.update { it.copy(sheet = value, preview = null) }
        if (value == JamSheet.NEW || value == JamSheet.MODELS) loadCatalog()
        if (value == JamSheet.NEW || value == JamSheet.REPOSITORIES) loadRepositories()
    }

    fun model(value: JamModel) {
        if (value in _state.value.models)
            _state.update { it.copy(model = value, sheet = JamSheet.NEW) }
    }

    fun repository(value: JamRepository?) {
        _state.update { it.copy(repository = value, sheet = JamSheet.NEW) }
    }

    fun loadCatalog() {
        catalog?.cancel()
        val fence = generation
        val account = _state.value.account
        _state.update {
            it.copy(
                catalogLoading = true,
                catalogError = false,
                models = emptyList(),
                modelErrors = emptyList(),
            )
        }
        catalog =
            viewModelScope.launch {
                try {
                    val response = api.models(account)
                    if (fence == generation)
                        _state.update {
                            it.copy(
                                models = response.models,
                                modelErrors = response.errors,
                                catalogLoading = false,
                                model = it.model?.takeIf { model -> model in response.models },
                            )
                        }
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    if (fence == generation)
                        _state.update { it.copy(catalogLoading = false, catalogError = true) }
                }
            }
    }

    private fun loadRepositories() {
        val fence = generation
        val account = _state.value.account
        viewModelScope.launch {
            try {
                val values = api.repositories(account).repositories
                if (fence == generation)
                    _state.update { it.copy(repositories = values, repositoryError = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                if (fence == generation) _state.update { it.copy(repositoryError = true) }
            }
        }
    }

    fun create() {
        val current = _state.value
        val model = current.model ?: return
        if (
            current.draft.isBlank() ||
                model !in current.models ||
                current.catalogLoading ||
                current.catalogError
        )
            return
        val request =
            CreateJam(
                current.draft.trim(),
                model.provider,
                model.id,
                current.repository?.fullName,
                current.repository?.defaultBranch,
            )
        val previous = createRequest
        val stable =
            if (previous?.copy(requestId = request.requestId) == request) previous else request
        createRequest = stable
        mutate { account ->
            val jam = api.create(account, stable)
            createRequest = null
            _state.update {
                it.copy(
                    selected = jam,
                    jams = (listOf(jam) + it.jams).distinctBy { row -> row.id },
                    sheet = null,
                    draft = "",
                )
            }
        }
    }

    fun send() {
        val current = _state.value
        val jam = current.selected ?: return
        if (current.reply.isBlank() || !jam.canMessage()) return
        val old = messageRequest?.takeIf { it.first == jam.id }?.second
        val request =
            old?.takeIf { it.content == current.reply.trim() } ?: SendMessage(current.reply.trim())
        messageRequest = jam.id to request
        mutate { account ->
            val updated = api.send(account, jam.id, request)
            messageRequest = null
            _state.update { it.copy(selected = merge(it.selected, updated), reply = "") }
        }
    }

    fun archive() {
        val jam = _state.value.selected ?: return
        mutate { account ->
            val updated =
                api.archive(
                    account,
                    jam.id,
                    ArchiveJam(if (jam.archiveStatus == "archived") "active" else "archived"),
                )
            _state.update {
                it.copy(
                    selected = merge(it.selected, updated),
                    jams = it.jams.map { row -> if (row.id == updated.id) updated else row },
                )
            }
        }
    }

    fun loadMore() {
        val current = _state.value
        mutate { account ->
            if (current.selected != null) {
                val before = current.selected.nextBefore ?: return@mutate
                val page = api.history(account, current.selected.id, before)
                _state.update {
                    it.copy(
                        selected =
                            it.selected?.copy(
                                messages =
                                    (page.messages + it.selected.messages).distinctBy { m -> m.id },
                                hasMore = page.hasMore,
                                nextBefore = page.nextBefore,
                            )
                    )
                }
            } else {
                val page = api.list(account, current.cursor ?: return@mutate)
                _state.update {
                    it.copy(
                        jams = (it.jams + page.jams).distinctBy { row -> row.id },
                        cursor = page.nextCursor,
                    )
                }
            }
        }
    }

    fun previewShip() {
        val jam = _state.value.selected ?: return
        if (!jam.canMessage() || jam.repository.isBlank()) return
        mutate { account ->
            val preview = api.shipPreview(account, jam.id)
            _state.update { it.copy(preview = preview, sheet = JamSheet.SHIP) }
        }
    }

    fun approveShip() {
        val jam = _state.value.selected ?: return
        val preview = _state.value.preview ?: return
        mutate { account ->
            val updated = api.ship(account, jam.id, ShipApproval(preview))
            _state.update {
                it.copy(selected = merge(it.selected, updated), preview = null, sheet = null)
            }
        }
    }

    private fun mutate(action: suspend (String) -> Unit) {
        val current = _state.value
        if (current.busy || !current.enabled || current.denied) return
        val fence = generation
        _state.update { it.copy(busy = true, error = false) }
        mutation =
            viewModelScope.launch {
                try {
                    action(current.account)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (fence == generation) failure(e, false)
                } finally {
                    if (fence == generation) _state.update { it.copy(busy = false) }
                }
                if (fence == generation) refresh(quiet = true)
            }
    }

    private fun failure(error: Exception, quiet: Boolean) {
        if (error is HttpException && error.code() in listOf(401, 403)) {
            generation++
            _state.update {
                JamsState(
                    enabled = it.enabled,
                    account = it.account,
                    denied = true,
                    loading = false,
                )
            }
        } else _state.update { it.copy(loading = false, error = !quiet || it.error) }
    }

    private fun merge(old: ServerJam?, fresh: ServerJam?): ServerJam? {
        if (fresh == null || old?.id != fresh.id) return fresh
        if ((fresh.revision ?: 0) < (old.revision ?: 0)) return old
        if (fresh.messages.none { incoming -> old.messages.any { it.id == incoming.id } })
            return fresh
        val firstFresh = fresh.messages.mapNotNull { it.position }.minOrNull()
        val hasEarlier =
            firstFresh != null &&
                old.messages.any { it.position != null && it.position < firstFresh }
        return fresh.copy(
            messages =
                (old.messages + fresh.messages)
                    .associateBy { it.id }
                    .values
                    .sortedBy { it.position ?: 0 },
            hasMore = if (hasEarlier) old.hasMore else fresh.hasMore,
            nextBefore = if (hasEarlier) old.nextBefore else fresh.nextBefore,
        )
    }
}

fun ServerJam.canMessage(): Boolean =
    archiveStatus != "archived" && status in listOf("idle", "failed", "interrupted")
