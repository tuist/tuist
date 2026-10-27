package dev.tuist.gradle

import com.google.gson.Gson

object JwtParser {
    fun decodePayload(jwt: String?): Map<String, Any>? {
        if (jwt == null) return null
        return try {
            val parts = jwt.split(".")
            if (parts.size != 3) return null
            val payload = parts[1]
            val padded = when (payload.length % 4) {
                2 -> "$payload=="
                3 -> "${payload}="
                else -> payload
            }
            val decoded = java.util.Base64.getUrlDecoder().decode(padded)
            val json = String(decoded, Charsets.UTF_8)
            @Suppress("UNCHECKED_CAST")
            Gson().fromJson(json, Map::class.java) as? Map<String, Any>
        } catch (_: Exception) {
            null
        }
    }

    fun isExpired(jwt: String?, bufferSeconds: Int = 30): Boolean {
        val payload = decodePayload(jwt) ?: return true
        val exp = (payload["exp"] as? Number)?.toLong() ?: return true
        val now = System.currentTimeMillis() / 1000
        return now >= (exp - bufferSeconds)
    }

    fun getExpirationMs(jwt: String?): Long? {
        val payload = decodePayload(jwt) ?: return null
        val exp = (payload["exp"] as? Number)?.toLong() ?: return null
        return exp * 1000
    }

    fun getType(jwt: String?): String? {
        val payload = decodePayload(jwt) ?: return null
        return payload["type"] as? String
    }
}
