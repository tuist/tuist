package dev.tuist.app.ui.projects

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.api.model.Project
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.projects.ProjectsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface ProjectsUiState {
    data object Loading : ProjectsUiState
    data class Success(val projects: List<Project>) : ProjectsUiState
    data class Error(val message: String) : ProjectsUiState
}

@HiltViewModel
class ProjectsViewModel @Inject constructor(
    private val projectsRepository: ProjectsRepository,
    private val authRepository: AuthRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ProjectsUiState>(ProjectsUiState.Loading)
    val uiState: StateFlow<ProjectsUiState> = _uiState.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    init {
        viewModelScope.launch {
            authRepository.authState.first { it is AuthState.LoggedIn }
            loadProjects()
        }
    }

    fun loadProjects() {
        viewModelScope.launch {
            _uiState.value = ProjectsUiState.Loading
            projectsRepository.listProjects()
                .onSuccess { _uiState.value = ProjectsUiState.Success(it) }
                .onFailure { _uiState.value = ProjectsUiState.Error(it.message ?: "Failed to load projects") }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _isRefreshing.value = true
            projectsRepository.listProjects()
                .onSuccess { _uiState.value = ProjectsUiState.Success(it) }
                .onFailure { _uiState.value = ProjectsUiState.Error(it.message ?: "Failed to load projects") }
            _isRefreshing.value = false
        }
    }

    fun signOut() {
        authRepository.signOut()
    }
}
