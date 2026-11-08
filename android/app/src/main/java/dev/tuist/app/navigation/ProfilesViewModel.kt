package dev.tuist.app.navigation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ProfilesViewModel @Inject constructor(val auth: AuthRepository) : ViewModel() {
    val loading = MutableStateFlow(false)
    val failed = MutableStateFlow(false)
    private var selection: Job? = null

    fun cancelSelection() { selection?.cancel() }

    fun select(profileId: String, selected: () -> Unit) {
        if (loading.value) return
        val session = auth.session.value
        selection = viewModelScope.launch {
            loading.value = true
            failed.value = false
            try {
                check(auth.session.value == session)
                auth.switchProfile(profileId)
                currentCoroutineContext().ensureActive()
                selected()
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { failed.value = true }
            finally { loading.value = false }
        }
    }
}
