package dev.tuist.app.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.home.HomeActivityException
import dev.tuist.app.data.home.HomeActivityFailure
import dev.tuist.app.data.home.HomeActivityItem
import dev.tuist.app.data.home.HomeActivityKind
import dev.tuist.app.data.home.HomeActivityRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class HomeActivitySection(
    val items: List<HomeActivityItem> = emptyList(),
    val isLoading: Boolean = false,
    val hasLoaded: Boolean = false,
    val error: HomeActivityFailure? = null,
)

data class HomeActivityUiState(
    val fullHandle: String? = null,
    val sections: Map<HomeActivityKind, HomeActivitySection> = emptyMap(),
    val isRefreshing: Boolean = false,
)

@HiltViewModel
class HomeActivityViewModel @Inject constructor(private val repository: HomeActivityRepository) : ViewModel() {
    private val _uiState = MutableStateFlow(HomeActivityUiState())
    val uiState = _uiState.asStateFlow()
    private var request = 0L
    private var loadJob: Job? = null

    fun selectProject(fullHandle: String?) {
        if (_uiState.value.fullHandle == fullHandle) return
        request += 1
        loadJob?.cancel()
        _uiState.value = HomeActivityUiState(fullHandle = fullHandle)
        if (fullHandle != null) loadAll(fullHandle, request)
    }

    fun refresh() {
        val handle = _uiState.value.fullHandle ?: return
        request += 1
        loadJob?.cancel()
        _uiState.update { it.copy(isRefreshing = true) }
        loadAll(handle, request)
    }

    fun retry(kind: HomeActivityKind) {
        val handle = _uiState.value.fullHandle ?: return
        if (_uiState.value.sections[kind]?.isLoading == true) return
        val version = request
        updateSection(kind) { it.copy(isLoading = true, error = null) }
        viewModelScope.launch { loadSection(kind, handle, version) }
    }

    private fun loadAll(handle: String, version: Long) {
        HomeActivityKind.entries.forEach { kind -> updateSection(kind) { it.copy(isLoading = true, error = null) } }
        loadJob = viewModelScope.launch {
            try {
                coroutineScope {
                    HomeActivityKind.entries.forEach { kind -> launch { loadSection(kind, handle, version) } }
                }
            } finally {
                if (isCurrent(handle, version)) _uiState.update { it.copy(isRefreshing = false) }
            }
        }
    }

    private suspend fun loadSection(kind: HomeActivityKind, handle: String, version: Long) {
        try {
            val items = repository.list(kind, handle)
            if (isCurrent(handle, version)) updateSection(kind) { it.copy(items = items.take(3), hasLoaded = true) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (isCurrent(handle, version)) {
                updateSection(kind) { it.copy(error = (e as? HomeActivityException)?.failure ?: HomeActivityFailure.Unavailable) }
            }
        } finally {
            if (isCurrent(handle, version)) updateSection(kind) { it.copy(isLoading = false) }
        }
    }

    private fun updateSection(kind: HomeActivityKind, transform: (HomeActivitySection) -> HomeActivitySection) {
        _uiState.update { it.copy(sections = it.sections + (kind to transform(it.sections[kind] ?: HomeActivitySection()))) }
    }

    private fun isCurrent(handle: String, version: Long) = request == version && _uiState.value.fullHandle == handle
}
