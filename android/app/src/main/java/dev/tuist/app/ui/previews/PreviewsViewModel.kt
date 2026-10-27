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
    ) : PreviewsUiState
    data class Empty(val message: String) : PreviewsUiState
    data class Error(val message: String) : PreviewsUiState
}

@HiltViewModel
class PreviewsViewModel @Inject constructor(
    private val previewsRepository: PreviewsRepository,
    private val authRepository: AuthRepository,
    @ApplicationContext context: Context,
) : ViewModel() {

    private val prefs = context.getSharedPreferences("tuist_previews", Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow<PreviewsUiState>(PreviewsUiState.Loading)
    val uiState: StateFlow<PreviewsUiState> = _uiState.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    private val _errorEvents = MutableSharedFlow<String>()
    val errorEvents: SharedFlow<String> = _errorEvents.asSharedFlow()

    private var currentPage = 1

    init {
        viewModelScope.launch {
            authRepository.authState.first { it is AuthState.LoggedIn }
            loadProjects()
        }
    }

    fun loadProjects() {
        viewModelScope.launch {
            _uiState.value = PreviewsUiState.Loading
            try {
                val projects = previewsRepository.listProjects()
                if (projects.isEmpty()) {
                    _uiState.value = PreviewsUiState.Empty("no_projects")
                    return@launch
                }
                val lastSelectedFullName = prefs.getString(KEY_SELECTED_PROJECT, null)
                val selected = projects.find { it.fullName == lastSelectedFullName } ?: projects.first()
                loadPreviewsForProject(selected, projects)
            } catch (e: Exception) {
                _uiState.value = PreviewsUiState.Error(e.message ?: "Failed to load projects")
            }
        }
    }

    fun selectProject(project: Project) {
        val currentState = _uiState.value
        if (currentState is PreviewsUiState.Success && currentState.selectedProject == project) return
        viewModelScope.launch {
            val projects = when (currentState) {
                is PreviewsUiState.Success -> currentState.projects
                else -> return@launch
            }
            _uiState.value = PreviewsUiState.Loading
            loadPreviewsForProject(project, projects)
        }
    }

    fun loadMorePreviews() {
        if (_isLoadingMore.value) return
        val currentState = _uiState.value
        if (currentState !is PreviewsUiState.Success || !currentState.hasMorePreviews) return

        viewModelScope.launch {
            _isLoadingMore.value = true
            try {
                val (accountHandle, projectHandle) = splitFullName(currentState.selectedProject.fullName)
                val nextPage = currentPage + 1
                val page = previewsRepository.listPreviews(
                    accountHandle = accountHandle,
                    projectHandle = projectHandle,
                    page = nextPage,
                )
                currentPage = nextPage
                _uiState.value = currentState.copy(
                    previews = currentState.previews + page.previews,
                    hasMorePreviews = page.hasNextPage,
                )
            } catch (e: Exception) {
                _errorEvents.emit(e.message ?: "Failed to load more previews")
            }
            _isLoadingMore.value = false
        }
    }

    fun refresh() {
        val currentState = _uiState.value
        if (currentState !is PreviewsUiState.Success) {
            loadProjects()
            return
        }
        viewModelScope.launch {
            _isRefreshing.value = true
            try {
                val (accountHandle, projectHandle) = splitFullName(currentState.selectedProject.fullName)
                currentPage = 1
                val page = previewsRepository.listPreviews(
                    accountHandle = accountHandle,
                    projectHandle = projectHandle,
                    page = 1,
                )
                _uiState.value = currentState.copy(
                    previews = page.previews,
                    hasMorePreviews = page.hasNextPage,
                )
            } catch (e: Exception) {
                _uiState.value = PreviewsUiState.Error(e.message ?: "Failed to refresh previews")
            }
            _isRefreshing.value = false
        }
    }

    fun signOut() {
        authRepository.signOut()
    }

    private suspend fun loadPreviewsForProject(project: Project, projects: List<Project>) {
        try {
            val (accountHandle, projectHandle) = splitFullName(project.fullName)
            currentPage = 1
            val page = previewsRepository.listPreviews(
                accountHandle = accountHandle,
                projectHandle = projectHandle,
                page = 1,
            )
            prefs.edit().putString(KEY_SELECTED_PROJECT, project.fullName).apply()
            _uiState.value = PreviewsUiState.Success(
                projects = projects,
                selectedProject = project,
                previews = page.previews,
                hasMorePreviews = page.hasNextPage,
            )
        } catch (e: Exception) {
            _uiState.value = PreviewsUiState.Error(e.message ?: "Failed to load previews")
        }
    }

    private fun splitFullName(fullName: String): Pair<String, String> {
        val parts = fullName.split("/", limit = 2)
        return Pair(parts[0], parts.getOrElse(1) { parts[0] })
    }

    companion object {
        private const val KEY_SELECTED_PROJECT = "selected_project"
    }
}
