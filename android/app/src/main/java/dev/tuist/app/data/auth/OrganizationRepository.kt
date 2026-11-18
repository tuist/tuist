package dev.tuist.app.data.auth

import dev.tuist.app.data.network.ProfileRequest
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

data class OrganizationChoice(
    val origin: String,
    val name: String,
    val personal: Boolean,
    val logins: List<TokenStorage.Profile>,
) {
    fun preferredLogin(activeProfileId: String?): TokenStorage.Profile = logins.firstOrNull { it.id == activeProfileId } ?: logins.first()
}

data class OrganizationChoices(val organizations: List<OrganizationChoice>, val incomplete: Boolean)

@Singleton
class OrganizationRepository @Inject constructor(private val tokens: TokenStorage, private val client: OkHttpClient) {
    suspend fun load(): OrganizationChoices = withContext(Dispatchers.IO) {
        var incomplete = false
        val rows = tokens.profiles.value.flatMap { profile ->
            var unavailable = false
            val names = try {
                memberships(profile).also { tokens.updateMemberships(profile.id, it) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                incomplete = true
                unavailable = true
                profile.memberships.orEmpty()
            }
            if (tokens.credentials(profile.id) == null) emptyList()
            else {
                val organizations = names.map { OrganizationChoice(profile.server, it, false, listOf(profile)) }
                val account = tokens.credentials(profile.id)?.let { JwtParser.parseAccount(it.access) }
                organizations + if (names.isEmpty() || unavailable) {
                    account?.let { listOf(OrganizationChoice(profile.server, it.handle, true, listOf(profile))) }.orEmpty()
                } else emptyList()
            }
        }
        OrganizationChoices(rows.groupBy { it.origin to it.name }.values.map { rowsForOrganization ->
            rowsForOrganization.first().copy(logins = rowsForOrganization.flatMap { it.logins })
        }.sortedWith(compareBy({ it.name.lowercase() }, { it.origin })), incomplete)
    }

    suspend fun validate(choice: OrganizationChoice, profileId: String): Boolean = withContext(Dispatchers.IO) {
        val profile = tokens.profiles.value.firstOrNull { it.id == profileId && it.server == choice.origin }
            ?: return@withContext false
        if (profileId !in choice.logins.map { it.id }) return@withContext false
        if (choice.personal) {
            tokens.credentials(profileId)?.let { JwtParser.parseAccount(it.access)?.handle } == choice.name
        } else try {
            choice.name in memberships(profile)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (e is MembershipFailure && e.code in listOf(401, 403)) false
            else tokens.credentials(profileId) != null && choice.name in profile.memberships.orEmpty()
        }
    }

    private fun memberships(profile: TokenStorage.Profile): List<String> {
        val request = Request.Builder().url(profile.server.trimEnd('/') + "/api/organizations")
            .tag(ProfileRequest::class.java, ProfileRequest(profile.id)).build()
        return client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw MembershipFailure(response.code)
            val array = JSONObject(response.body?.string() ?: throw IOException("Empty memberships")).getJSONArray("organizations")
            (0 until array.length()).map { array.getJSONObject(it).getString("name") }.distinct()
        }
    }

    private class MembershipFailure(val code: Int) : IOException("Organization discovery failed: $code")
}
