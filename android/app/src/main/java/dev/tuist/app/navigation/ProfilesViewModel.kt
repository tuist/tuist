package dev.tuist.app.navigation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.auth.OrganizationChoice
import dev.tuist.app.data.auth.OrganizationChoices
import dev.tuist.app.data.auth.OrganizationRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ProfilesViewModel @Inject constructor(val auth: AuthRepository, private val organizations: OrganizationRepository) : ViewModel() {
    val choices = MutableStateFlow(OrganizationChoices(emptyList(), false))
    val loading = MutableStateFlow(false)
    val failed = MutableStateFlow(false)
    private var selection: Job? = null

    fun cancelSelection() { selection?.cancel() }

    fun load() {
        if (loading.value) return
        viewModelScope.launch {
            loading.value = true
            failed.value = false
            try { choices.value = organizations.load() }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { failed.value = true }
            finally { loading.value = false }
        }
    }

    fun select(choice: OrganizationChoice, profileId: String, selected: () -> Unit) {
        if (loading.value) return
        val session = auth.session.value
        selection = viewModelScope.launch {
            loading.value = true
            failed.value = false
            try {
                check(organizations.validate(choice, profileId))
                check(auth.session.value == session)
                auth.selectOrganization(profileId, if (choice.personal) null else choice.name)
                selected()
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { failed.value = true }
            finally { loading.value = false }
        }
    }
}
