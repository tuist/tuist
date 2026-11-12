package dev.tuist.app.data.push

import com.squareup.moshi.Moshi
import dev.tuist.app.api.NotificationRulesApi
import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.api.PushDevicesApi
import dev.tuist.app.api.model.CreateNotificationRule1
import dev.tuist.app.api.model.ListPushDevices200ResponseDevicesInner
import dev.tuist.app.api.model.NotificationRule1
import dev.tuist.app.api.model.NotificationRuleAction1
import dev.tuist.app.api.model.UpdateNotificationRule1
import retrofit2.Response
import javax.inject.Inject
import javax.inject.Singleton

typealias PushDevice = ListPushDevices200ResponseDevicesInner

/** A text condition: one exact value, or text it contains, ignoring case. */
sealed interface ValueMatch {
    val value: String

    data class Is(override val value: String) : ValueMatch
    data class Contains(override val value: String) : ValueMatch
}

/**
 * One of the signed-in user's notification rules: when [event] happens in one of [projects] (any project when it's
 * empty) and the event meets the conditions, run [actions].
 */
data class NotificationRule(
    val id: String? = null,
    val event: String = EVENT_PREVIEW_PUBLISHED,
    val isEnabled: Boolean = true,
    /** `account/project` handles. */
    val projects: List<String> = emptyList(),
    val track: ValueMatch? = null,
    val gitBranch: ValueMatch? = null,
    /** Only previews the user published. */
    val publishedByMe: Boolean = false,
    val actions: List<String> = listOf(ACTION_PUSH),
) {
    companion object {
        const val EVENT_PREVIEW_PUBLISHED = "preview_published"
        const val ACTION_PUSH = "push"
    }
}

/** [code] is the HTTP status of the failed response. */
class NotificationsError(message: String, val code: Int? = null) : Exception(message) {
    /**
     * The server predates notification rules (404), or only accepts these requests from its own Tuist app client
     * (403), which self-hosted sign-ins aren't.
     */
    val isUnsupported: Boolean get() = code == 403 || code == 404
}

@Singleton
class NotificationsRepository @Inject constructor(
    private val pushDevicesApi: PushDevicesApi,
    private val rulesApi: NotificationRulesApi,
    private val projectsApi: ProjectsApi,
    private val moshi: Moshi,
) {
    suspend fun listDevices(): List<PushDevice> =
        pushDevicesApi.listPushDevices().bodyOrThrow("The devices could not be listed").devices

    suspend fun removeDevice(registrationId: String) {
        val response = pushDevicesApi.removePushDevice(registrationId)
        if (!response.isSuccessful) throw response.error("The device could not be removed")
    }

    /** `account/project` handles of the projects the user can pick for a rule, sorted. */
    suspend fun listProjects(): List<String> =
        projectsApi.listProjects().bodyOrThrow("The projects could not be listed").projects.map { it.fullName }.sorted()

    suspend fun listRules(): List<NotificationRule> =
        rulesApi.listNotificationRules().bodyOrThrow("The notification rules could not be loaded").rules.map { it.toRule() }

    suspend fun createRule(rule: NotificationRule): NotificationRule =
        rulesApi.createNotificationRule(
            CreateNotificationRule1(
                actions = rule.actions.map(::NotificationRuleAction1),
                event = rule.event,
                conditions = rule.conditions(),
                enabled = rule.isEnabled,
                projects = rule.projects,
            ),
        ).bodyOrThrow("The notification rule could not be saved").toRule()

    /** Saves every field of [rule] except its event, which can't change. */
    suspend fun updateRule(rule: NotificationRule): NotificationRule =
        rulesApi.updateNotificationRule(
            requireNotNull(rule.id),
            UpdateNotificationRule1(
                actions = rule.actions.map(::NotificationRuleAction1),
                conditions = rule.conditions(),
                enabled = rule.isEnabled,
                projects = rule.projects,
            ),
        ).bodyOrThrow("The notification rule could not be saved").toRule()

    suspend fun deleteRule(id: String) {
        val response = rulesApi.deleteNotificationRule(id)
        // 404: already deleted, for example from another device.
        if (!response.isSuccessful && response.code() != 404) {
            throw response.error("The notification rule could not be deleted")
        }
    }

    /** Values the user can pick for [event]'s conditions in a project, keyed by condition, such as `track`. */
    suspend fun conditionOptions(event: String, projectFullHandle: String): Map<String, List<String>> {
        val handles = projectFullHandle.split("/", limit = 2)
        if (handles.size != 2) return emptyMap()
        val response = rulesApi.listNotificationConditionOptions(event, handles[0], handles[1])
        // 404: the project can't get these notifications, so there's nothing to suggest.
        if (response.code() == 404) return emptyMap()
        return response.bodyOrThrow("The suggestions could not be loaded").options
    }

    private fun <T> Response<T>.bodyOrThrow(action: String): T {
        val body = body()
        if (isSuccessful && body != null) return body
        throw error(action)
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
            code = code(),
        )
    }
}

internal fun NotificationRule.conditions(): Map<String, Any> = buildMap {
    track?.let { put("track", it.toJson()) }
    gitBranch?.let { put("git_branch", it.toJson()) }
    put("published_by", if (publishedByMe) "me" else "anyone")
}

private fun ValueMatch.toJson(): Map<String, String> = mapOf(
    "operator" to if (this is ValueMatch.Contains) "contains" else "is",
    "value" to value,
)

internal fun NotificationRule1.toRule(): NotificationRule = NotificationRule(
    id = id.toString(),
    event = event,
    isEnabled = enabled,
    projects = projects,
    track = conditions["track"].toValueMatch(),
    gitBranch = conditions["git_branch"].toValueMatch(),
    publishedByMe = conditions["published_by"] == "me",
    actions = actions.map { it.type },
)

/** Newer servers can add operators; a condition this app can't show is left out rather than misread. */
private fun Any?.toValueMatch(): ValueMatch? {
    val match = this as? Map<*, *> ?: return null
    val value = match["value"] as? String ?: return null
    return when (match["operator"]) {
        "is" -> ValueMatch.Is(value)
        "contains" -> ValueMatch.Contains(value)
        else -> null
    }
}
