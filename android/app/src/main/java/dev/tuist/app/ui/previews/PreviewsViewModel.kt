package dev.tuist.app.ui.previews

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.tuist.app.api.model.Preview
import dev.tuist.app.api.model.Project
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.previews.PreviewsRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface PreviewsUiState {
    data object Loading : PreviewsUiState
    data class Success(
        val projects: List<Project>,
        val selectedProject: Project,
        val previews: List<Preview>,
        val hasMorePreviews: Boolean,
    ) : PreviewsUiState {
        val recentPreviews: List<Preview>
            get() = previews.take(3)
    }
    data class Empty(val message: String) : PreviewsUiState
    data class Error(val message: String) : PreviewsUiState
}

data class PreviewsProjectContext(val projects: List<Project> = emptyList(), val selectedProject: Project? = null)

@HiltViewModel
class PreviewsViewModel @Inject constructor(
    private val previewsRepository: PreviewsRepository,
    private val authRepository: AuthRepository,
    @ApplicationContext context: Context,
) : ViewModel() {
    private val prefs = context.getSharedPreferences("tuist_previews", Context.MODE_PRIVATE)
    private val _uiState = MutableStateFlow<PreviewsUiState>(PreviewsUiState.Loading)
    val uiState: StateFlow<PreviewsUiState> = _uiState.asStateFlow()
    private val _projectContext = MutableStateFlow(PreviewsProjectContext())
    val projectContext: StateFlow<PreviewsProjectContext> = _projectContext.asStateFlow()
    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()
    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()
    private val _errorEvents = MutableSharedFlow<String>()
    val errorEvents: SharedFlow<String> = _errorEvents.asSharedFlow()
    private var currentPage = 1
    private var requestVersion = 0L

    init {
        viewModelScope.launch {
            authRepository.authState.first { it is AuthState.LoggedIn }
            loadProjects()
        }
    }

    fun loadProjects() {
        val request = beginRequest()
        _uiState.value = PreviewsUiState.Loading
        viewModelScope.launch {
            try {
                val projects = previewsRepository.listProjects()
                if (request != requestVersion) return@launch
                if (projects.isEmpty()) {
                    _projectContext.value = PreviewsProjectContext()
                    _uiState.value = PreviewsUiState.Empty("no_projects")
                    return@launch
                }
                val lastSelected = _projectContext.value.selectedProject?.fullName
                    ?: prefs.getString(KEY_SELECTED_PROJECT, null)
                val selected = projects.find { it.fullName == lastSelected } ?: projects.first()
                selectContext(selected, projects)
                loadPreviewsForProject(selected, projects, request)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (request == requestVersion) {
                    _uiState.value = PreviewsUiState.Error(e.message ?: "Failed to load projects")
                }
            }
        }
    }

    fun selectProject(project: Project) {
        val context = _projectContext.value
        if (context.selectedProject?.fullName == project.fullName || context.projects.none { it.fullName == project.fullName }) return
        val request = beginRequest()
        selectContext(project, context.projects)
        _uiState.value = PreviewsUiState.Loading
        viewModelScope.launch { loadPreviewsForProject(project, context.projects, request) }
    }

    fun loadMorePreviews() {
        if (_isLoadingMore.value) return
        val current = _uiState.value as? PreviewsUiState.Success ?: return
        if (!current.hasMorePreviews) return
        val request = requestVersion
        _isLoadingMore.value = true
        viewModelScope.launch {
            try {
                val (account, project) = splitFullName(current.selectedProject.fullName)
                val nextPage = currentPage + 1
                val page = previewsRepository.listPreviews(accountHandle = account, projectHandle = project, page = nextPage)
                if (!isCurrent(request, current.selectedProject.fullName)) return@launch
                currentPage = nextPage
                _uiState.value = current.copy(
                    previews = (current.previews + page.previews).distinctBy { it.id },
                    hasMorePreviews = page.hasNextPage,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (isCurrent(request, current.selectedProject.fullName)) {
                    _errorEvents.emit(e.message ?: "Failed to load more previews")
                }
            } finally {
                if (request == requestVersion) _isLoadingMore.value = false
            }
        }
    }

    fun refresh() {
        val context = _projectContext.value
        val selected = context.selectedProject ?: return loadProjects()
        val request = beginRequest()
        _isRefreshing.value = true
        viewModelScope.launch {
            try {
                val (account, project) = splitFullName(selected.fullName)
                val page = previewsRepository.listPreviews(accountHandle = account, projectHandle = project, page = 1)
                if (!isCurrent(request, selected.fullName)) return@launch
                currentPage = 1
                _uiState.value = PreviewsUiState.Success(context.projects, selected, page.previews, page.hasNextPage)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (isCurrent(request, selected.fullName)) {
                    _uiState.value = PreviewsUiState.Error(e.message ?: "Failed to refresh previews")
                }
            } finally {
                if (request == requestVersion) _isRefreshing.value = false
            }
        }
    }

    fun signOut() = authRepository.signOut()

    private fun beginRequest(): Long {
        requestVersion += 1
        _isLoadingMore.value = false
        _isRefreshing.value = false
        return requestVersion
    }

    private fun selectContext(project: Project, projects: List<Project>) {
        _projectContext.value = PreviewsProjectContext(projects, project)
        prefs.edit().putString(KEY_SELECTED_PROJECT, project.fullName).apply()
    }

    private suspend fun loadPreviewsForProject(project: Project, projects: List<Project>, request: Long) {
        try {
            val (account, handle) = splitFullName(project.fullName)
            val page = previewsRepository.listPreviews(accountHandle = account, projectHandle = handle, page = 1)
            if (!isCurrent(request, project.fullName)) return
            currentPage = 1
            _uiState.value = PreviewsUiState.Success(projects, project, page.previews, page.hasNextPage)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (isCurrent(request, project.fullName)) {
                _uiState.value = PreviewsUiState.Error(e.message ?: "Failed to load previews")
            }
        }
    }

    private fun isCurrent(request: Long, fullName: String) =
        request == requestVersion && _projectContext.value.selectedProject?.fullName == fullName

    private fun splitFullName(fullName: String): Pair<String, String> {
        val parts = fullName.split("/", limit = 2)
        return Pair(parts[0], parts.getOrElse(1) { parts[0] })
    }

    companion object {
        private const val KEY_SELECTED_PROJECT = "selected_project"
    }
}
