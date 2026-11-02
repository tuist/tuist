package dev.tuist.app.data.push

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import dev.tuist.app.api.NotificationPreferencesApi
import dev.tuist.app.api.model.NotificationPreferences1
import dev.tuist.app.api.model.NotificationPreferencesAccount1
import dev.tuist.app.api.model.NotificationPreferencesProject1
import dev.tuist.app.api.model.UpdateAccountNotificationPreferenceRequest
import dev.tuist.app.api.model.UpdateProjectNotificationPreferenceRequest
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import retrofit2.Response

class NotificationsRepositoryTest {

    private lateinit var preferencesApi: NotificationPreferencesApi
    private lateinit var repository: NotificationsRepository

    private val response = NotificationPreferences1(
        kind = "new_preview",
        accounts = listOf(
            NotificationPreferencesAccount1(
                handle = "tuist",
                enabled = false,
                projects = listOf(
                    NotificationPreferencesProject1(enabled = false, handle = "app", setting = NotificationPreferencesProject1.Setting.default),
                    NotificationPreferencesProject1(enabled = true, handle = "cli", setting = NotificationPreferencesProject1.Setting.on),
                ),
            ),
        ),
    )

    private val expected = listOf(
        AccountNotificationPreference(
            handle = "tuist",
            enabled = false,
            projects = listOf(
                ProjectNotificationPreference("app", ProjectNotificationSetting.Default, enabled = false),
                ProjectNotificationPreference("cli", ProjectNotificationSetting.On, enabled = true),
            ),
        ),
    )

    @Before
    fun setUp() {
        preferencesApi = mockk()
        val moshi = Moshi.Builder().addLast(KotlinJsonAdapterFactory()).build()
        repository = NotificationsRepository(mockk(), preferencesApi, moshi)
    }

    @Test
    fun `maps the new preview preferences`() = runTest {
        coEvery { preferencesApi.getNotificationPreferences("new_preview") } returns Response.success(response)

        assertEquals(expected, repository.newPreviewPreferences())
    }

    @Test
    fun `updating an account returns the refreshed preferences`() = runTest {
        coEvery {
            preferencesApi.updateAccountNotificationPreference("new_preview", "tuist", UpdateAccountNotificationPreferenceRequest(enabled = false))
        } returns Response.success(response)

        assertEquals(expected, repository.updateNewPreviewAccount("tuist", false))
    }

    @Test
    fun `updating a project sends the setting and returns the refreshed preferences`() = runTest {
        coEvery {
            preferencesApi.updateProjectNotificationPreference(
                "new_preview",
                "tuist",
                "cli",
                UpdateProjectNotificationPreferenceRequest(setting = UpdateProjectNotificationPreferenceRequest.Setting.on),
            )
        } returns Response.success(response)

        assertEquals(expected, repository.updateNewPreviewProject("tuist", "cli", ProjectNotificationSetting.On))
    }

    @Test
    fun `failures surface the server message`() = runTest {
        coEvery {
            preferencesApi.updateProjectNotificationPreference(any(), any(), any(), any())
        } returns Response.error(404, """{"message":"The project was not found"}""".toResponseBody())

        val error = assertThrows(NotificationsError::class.java) {
            kotlinx.coroutines.runBlocking { repository.updateNewPreviewProject("tuist", "gone", ProjectNotificationSetting.Off) }
        }
        assertEquals("The project was not found", error.message)
    }
}
