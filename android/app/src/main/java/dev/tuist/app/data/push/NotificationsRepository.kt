package dev.tuist.app.data.push

import com.squareup.moshi.Moshi
import dev.tuist.app.api.NotificationPreferencesApi
import dev.tuist.app.api.PushDevicesApi
import dev.tuist.app.api.model.ListPushDevices200ResponseDevicesInner
import dev.tuist.app.api.model.NotificationPreferences
import dev.tuist.app.api.model.UpdateAccountNotificationPreferenceRequest
import dev.tuist.app.api.model.UpdateProjectNotificationPreferenceRequest
import retrofit2.Response
import javax.inject.Inject
import javax.inject.Singleton

typealias PushDevice = ListPushDevices200ResponseDevicesInner

enum class ProjectNotificationSetting { Default, On, Off }

data class ProjectNotificationPreference(
    val handle: String,
    val setting: ProjectNotificationSetting,
    /** The effective value: the account's choice for [ProjectNotificationSetting.Default], otherwise the override. */
    val enabled: Boolean,
)

data class AccountNotificationPreference(
    val handle: String,
    val enabled: Boolean,
    val projects: List<ProjectNotificationPreference>,
)

class NotificationsError(message: String) : Exception(message)

@Singleton
class NotificationsRepository @Inject constructor(
    private val pushDevicesApi: PushDevicesApi,
    private val preferencesApi: NotificationPreferencesApi,
    private val moshi: Moshi,
) {
    suspend fun listDevices(): List<PushDevice> {
        val response = pushDevicesApi.listPushDevices()
        val body = response.body()
        if (response.isSuccessful && body != null) return body.devices
        throw response.error("The devices could not be listed")
    }

    suspend fun removeDevice(registrationId: String) {
        val response = pushDevicesApi.removePushDevice(registrationId)
        if (response.isSuccessful) return
        throw response.error("The device could not be removed")
    }

    suspend fun newPreviewPreferences(): List<AccountNotificationPreference> =
        preferencesApi.getNotificationPreferences(KIND_NEW_PREVIEW)
            .preferences("The notification preferences could not be loaded")

    suspend fun updateNewPreviewAccount(accountHandle: String, enabled: Boolean): List<AccountNotificationPreference> =
        preferencesApi.updateAccountNotificationPreference(
            kind = KIND_NEW_PREVIEW,
            accountHandle = accountHandle,
            updateAccountNotificationPreferenceRequest = UpdateAccountNotificationPreferenceRequest(enabled = enabled),
        ).preferences("The notification preference could not be saved")

    suspend fun updateNewPreviewProject(
        accountHandle: String,
        projectHandle: String,
        setting: ProjectNotificationSetting,
    ): List<AccountNotificationPreference> =
        preferencesApi.updateProjectNotificationPreference(
            kind = KIND_NEW_PREVIEW,
            accountHandle = accountHandle,
            projectHandle = projectHandle,
            updateProjectNotificationPreferenceRequest = UpdateProjectNotificationPreferenceRequest(
                setting = when (setting) {
                    ProjectNotificationSetting.Default -> UpdateProjectNotificationPreferenceRequest.Setting.default
                    ProjectNotificationSetting.On -> UpdateProjectNotificationPreferenceRequest.Setting.on
                    ProjectNotificationSetting.Off -> UpdateProjectNotificationPreferenceRequest.Setting.off
                },
            ),
        ).preferences("The notification preference could not be saved")

    private fun Response<NotificationPreferences>.preferences(action: String): List<AccountNotificationPreference> {
        val body = body()
        if (!isSuccessful || body == null) throw error(action)
        return body.accounts.map { account ->
            AccountNotificationPreference(
                handle = account.handle,
                enabled = account.enabled,
                projects = account.projects.map { project ->
                    ProjectNotificationPreference(
                        handle = project.handle,
                        // Newer servers can add settings; `enabled` stays the effective choice.
                        setting = when (project.setting) {
                            "on" -> ProjectNotificationSetting.On
                            "off" -> ProjectNotificationSetting.Off
                            else -> ProjectNotificationSetting.Default
                        },
                        enabled = project.enabled,
                    )
                },
            )
        }
    }

    private fun <T> Response<T>.error(action: String): NotificationsError {
        val message = try {
            errorBody()?.string()?.let {
                moshi.adapter(dev.tuist.app.api.model.Error::class.java).fromJson(it)?.message
            }
        } catch (_: Exception) {
            null
        }
        return NotificationsError(
            message?.takeIf { it.isNotBlank() } ?: "$action due to an unknown Tuist response of ${code()}.",
        )
    }

    companion object {
        const val KIND_NEW_PREVIEW = "new_preview"
    }
}
