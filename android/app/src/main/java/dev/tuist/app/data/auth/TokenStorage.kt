package dev.tuist.app.data.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton
import dev.tuist.app.data.EnvironmentConfig
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

@Singleton
class TokenStorage internal constructor(
    private val prefs: SharedPreferences,
    private val server: String,
    private val issuingClientId: String? = null,
) {
    @Inject constructor(@ApplicationContext context: Context, environment: EnvironmentConfig) : this(
        encryptedPreferences(context), environment.serverUrl, environment.oauthClientId,
    )

    data class Profile(val id: String, val server: String, val label: String, val memberships: List<String>? = null, val organization: String? = null)
    data class Session(val profileId: String?, val generation: Long, val organization: String? = null, val origin: String? = null)
    data class Credentials(val profileId: String, val server: String, val access: String, val refresh: String, val clientId: String? = null)
    private data class Saved(val id: String, val server: String, val access: String, val refresh: String, val memberships: List<String>? = null, val organization: String? = null, val clientId: String? = null)
    private val saved = mutableListOf<Saved>()
    private var pendingRotation = false
    private var activeId: String? = null
    private var organization: String? = null
    private val _session = MutableStateFlow(Session(null, 0))
    val session: StateFlow<Session> = _session.asStateFlow()
    private val _profiles = MutableStateFlow<List<Profile>>(emptyList())
    val profiles: StateFlow<List<Profile>> = _profiles.asStateFlow()
    private val _accessTokenFlow = MutableStateFlow<String?>(null)
    val accessTokenFlow: StateFlow<String?> = _accessTokenFlow.asStateFlow()

    init {
        val encoded = prefs.getString("profiles_v1", null)
        if (encoded != null) {
            val array = JSONArray(encoded)
            for (i in 0 until array.length()) {
                val value = array.getJSONObject(i)
                val memberships = value.optJSONArray("memberships")?.let { names -> (0 until names.length()).map { names.getString(it) } }
                val origin = value.getString("server")
                val clientId = value.optString("client_id").ifEmpty { null } ?: issuingClientId.takeIf { origin == server }
                saved += Saved(value.getString("id"), origin, value.getString("access"), value.getString("refresh"), memberships, value.optString("organization").ifEmpty { null }, clientId)
            }
            activeId = prefs.getString("active_profile", null)?.takeIf { id -> saved.any { it.id == id } }
            organization = prefs.getString("active_organization", null).takeIf { activeId != null }
        } else {
            val access = prefs.getString(KEY_ACCESS_TOKEN, null)
            if (access != null) {
                val legacy = Saved(UUID.randomUUID().toString(), server, access, prefs.getString(KEY_REFRESH_TOKEN, "").orEmpty(), clientId = issuingClientId)
                saved += legacy
                activeId = legacy.id
            }
        }
        publish()
        persist(saved.toList(), activeId, selectedOrganization = organization)
    }

    @Synchronized fun storeTokens(accessToken: String, refreshToken: String, origin: String = server, clientId: String? = issuingClientId) {
        val existing = saved.firstOrNull { it.server == origin && identity(it.access) == identity(accessToken) }
        val profile = Saved(existing?.id ?: UUID.randomUUID().toString(), origin, accessToken, refreshToken, existing?.memberships, existing?.organization, clientId ?: existing?.clientId)
        val candidate = if (existing == null) saved + profile else saved.map { if (it.id == profile.id) profile else it }
        check(persist(candidate, profile.id, newSession = true, selectedOrganization = profile.organization))
    }

    @Synchronized fun getAccessToken(): String? = active()?.access
    @Synchronized fun getRefreshToken(): String? = active()?.refresh
    @Synchronized fun credentials(id: String): Credentials? = saved.firstOrNull { it.id == id }?.let {
        Credentials(it.id, it.server, it.access, it.refresh, it.clientId)
    }
    @Synchronized fun selectedAccount(): String? = organization ?: active()?.let { JwtParser.parseAccount(it.access)?.handle }
    @Synchronized fun selectedServer(): String = active()?.server ?: server
    @Synchronized fun snapshot(): Session = _session.value
    @Synchronized fun isCurrent(session: Session): Boolean = _session.value == session

    @Synchronized fun rotate(session: Session, oldRefresh: String, access: String, refresh: String): Boolean {
        val current = saved.firstOrNull { it.id == session.profileId } ?: return false
        if (current.refresh != oldRefresh) return false
        // The server has spent this refresh token even if its profile is no longer selected.
        val rotated = saved.map { if (it.id == current.id) it.copy(access = access, refresh = refresh) else it }
        if (persist(rotated, activeId, selectedOrganization = organization)) return true
        saved.clear()
        saved.addAll(rotated)
        pendingRotation = true
        publish()
        return false
    }

    @Synchronized fun retryPendingRotation(): Boolean {
        return !pendingRotation || persist(saved.toList(), activeId, selectedOrganization = organization)
    }

    @Synchronized fun switchProfile(id: String) {
        require(saved.any { it.id == id })
        if (id == activeId) { check(retryPendingRotation()); return }
        check(persist(saved.toList(), id, newSession = true, selectedOrganization = saved.first { it.id == id }.organization))
    }

    @Synchronized fun selectOrganization(id: String, name: String?) {
        require(saved.any { it.id == id })
        if (activeId == id && organization == name) { check(retryPendingRotation()); return }
        check(persist(saved.toList(), id, newSession = true, selectedOrganization = name))
    }

    @Synchronized fun updateMemberships(id: String, names: List<String>) {
        val profile = saved.firstOrNull { it.id == id } ?: return
        val memberships = names.distinct().sorted()
        val selected = profile.organization?.takeIf { it in memberships } ?: memberships.firstOrNull()
        val candidate = saved.map { if (it.id == id) it.copy(memberships = memberships, organization = selected) else it }
        check(persist(candidate, activeId, newSession = id == activeId && organization != selected,
            selectedOrganization = if (id == activeId) selected else organization))
    }

    @Synchronized fun removeRejectedProfile(id: String, refresh: String): Boolean {
        val profile = saved.firstOrNull { it.id == id && it.refresh == refresh } ?: return false
        if (profile.id == activeId) return false
        return persist(saved.filterNot { it.id == id }, activeId, selectedOrganization = organization)
    }

    @Synchronized fun clearIfCurrent(session: Session, selectFallback: Boolean = false): Boolean {
        if (!isCurrent(session)) return false
        clear(selectFallback)
        return true
    }

    @Synchronized fun clear(selectFallback: Boolean = false) {
        val remaining = saved.filterNot { it.id == activeId }
        val fallback = remaining.firstOrNull().takeIf { selectFallback }
        check(persist(remaining, fallback?.id, newSession = true, selectedOrganization = fallback?.organization))
    }

    private fun active() = saved.firstOrNull { it.id == activeId }

    private fun persist(candidate: List<Saved>, selected: String?, newSession: Boolean = false, selectedOrganization: String? = null): Boolean {
        val updated = candidate.map { if (it.id == selected) it.copy(organization = selectedOrganization) else it }
        val array = JSONArray()
        updated.forEach { profile ->
            val value = JSONObject().put("id", profile.id).put("server", profile.server).put("access", profile.access).put("refresh", profile.refresh)
                .put("organization", profile.organization.orEmpty())
                .put("client_id", profile.clientId.orEmpty())
            profile.memberships?.let { value.put("memberships", JSONArray(it)) }
            array.put(value)
        }
        val keys = listOf("profiles_v1", "active_profile", "active_organization", KEY_ACCESS_TOKEN, KEY_REFRESH_TOKEN)
        val previous = keys.associateWith { prefs.getString(it, null) }
        if (!prefs.edit().putString("profiles_v1", array.toString()).putString("active_profile", selected).putString("active_organization", selectedOrganization)
                .remove(KEY_ACCESS_TOKEN).remove(KEY_REFRESH_TOKEN).commit()) {
            // SharedPreferences updates its memory cache even when the disk write fails.
            val restore = prefs.edit()
            previous.forEach { (key, value) -> restore.putString(key, value) }
            restore.commit()
            return false
        }
        saved.clear()
        saved.addAll(updated)
        pendingRotation = false
        activeId = selected
        organization = selectedOrganization
        publish(newSession)
        return true
    }

    private fun publish(newSession: Boolean = false) {
        _session.value = Session(activeId, _session.value.generation + if (newSession) 1 else 0, organization, active()?.server)
        _profiles.value = saved.map {
            Profile(it.id, it.server, JwtParser.parseAccount(it.access)?.email ?: it.server, it.memberships, it.organization)
        }
        _accessTokenFlow.value = active()?.access
    }

    private fun identity(token: String): String = try {
        val payload = JSONObject(String(android.util.Base64.decode(token.split('.')[1], android.util.Base64.URL_SAFE)))
        payload.optString("sub").ifEmpty { payload.getString("email") }
    } catch (_: Exception) { token }

    companion object {
        private fun encryptedPreferences(context: Context): SharedPreferences = EncryptedSharedPreferences.create(
            context, "tuist_secure_prefs",
            MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
    }
}
