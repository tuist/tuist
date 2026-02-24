package dev.tuist.app.data.auth

import android.util.Base64
import android.util.Log
import dev.tuist.app.data.model.Account
import org.json.JSONObject

object JwtParser {

    private const val TAG = "JwtParser"

    fun parseAccount(jwt: String): Account? {
        val parts = jwt.split(".")
        if (parts.size != 3) return null

        return try {
            val payload = String(
                Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP),
            )
            val json = JSONObject(payload)
            val email = json.optString("email").takeIf { it.isNotEmpty() } ?: return null
            val handle = json.optString("preferred_username").takeIf { it.isNotEmpty() } ?: return null
            Account(email = email, handle = handle)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse JWT payload", e)
            null
        }
    }
}
