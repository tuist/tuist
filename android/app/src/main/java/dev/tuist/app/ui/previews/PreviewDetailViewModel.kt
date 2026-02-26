package dev.tuist.app.ui.previews

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.api.model.Preview
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.previews.PreviewsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface PreviewDetailUiState {
    data object Loading : PreviewDetailUiState
    data class Success(val preview: Preview) : PreviewDetailUiState
    data class Error(val message: String) : PreviewDetailUiState
}

@HiltViewModel
class PreviewDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val previewsRepository: PreviewsRepository,
    environmentConfig: EnvironmentConfig,
) : ViewModel() {

    private val previewId: String = checkNotNull(savedStateHandle["previewId"])
    val fullHandle: String = checkNotNull(savedStateHandle["fullHandle"])

    private val _uiState = MutableStateFlow<PreviewDetailUiState>(PreviewDetailUiState.Loading)
    val uiState: StateFlow<PreviewDetailUiState> = _uiState.asStateFlow()

    private val _isDeleting = MutableStateFlow(false)
    val isDeleting: StateFlow<Boolean> = _isDeleting.asStateFlow()

    val serverUrl: String = environmentConfig.serverUrl

    private val accountHandle: String
    private val projectHandle: String

    init {
        val parts = fullHandle.split("/", limit = 2)
        accountHandle = parts[0]
        projectHandle = parts.getOrElse(1) { parts[0] }
        loadPreview()
    }

    fun loadPreview() {
        viewModelScope.launch {
            _uiState.value = PreviewDetailUiState.Loading
            try {
                val preview = previewsRepository.getPreview(
                    accountHandle = accountHandle,
                    projectHandle = projectHandle,
                    previewId = previewId,
                )
                _uiState.value = PreviewDetailUiState.Success(preview)
            } catch (e: Exception) {
                _uiState.value = PreviewDetailUiState.Error(e.message ?: "Failed to load preview")
            }
        }
    }

    fun deletePreview(onDeleted: () -> Unit) {
        if (_isDeleting.value) return
        viewModelScope.launch {
            _isDeleting.value = true
            try {
                previewsRepository.deletePreview(
                    accountHandle = accountHandle,
                    projectHandle = projectHandle,
                    previewId = previewId,
                )
                onDeleted()
            } catch (e: Exception) {
                _uiState.value = PreviewDetailUiState.Error(e.message ?: "Failed to delete preview")
            }
            _isDeleting.value = false
        }
    }
}
