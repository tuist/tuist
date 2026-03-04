package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class JwtUtilsTest {

    private fun createJwt(claims: Map<String, Any>): String {
        val header = Base64.getUrlEncoder().withoutPadding()
            .encodeToString("""{"alg":"HS256","typ":"JWT"}""".toByteArray())
        val payload = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(Gson().toJson(claims).toByteArray())
        val signature = Base64.getUrlEncoder().withoutPadding()
            .encodeToString("signature".toByteArray())
        return "$header.$payload.$signature"
    }

    @Test
    fun `decodePayload returns claims from valid JWT`() {
        val jwt = createJwt(mapOf("sub" to "user123", "exp" to 9999999999L))
        val payload = JwtUtils.decodePayload(jwt)
        assertNotNull(payload)
        assertEquals("user123", payload["sub"])
    }

    @Test
    fun `decodePayload returns null for invalid JWT`() {
        assertNull(JwtUtils.decodePayload("not-a-jwt"))
        assertNull(JwtUtils.decodePayload("a.b"))
        assertNull(JwtUtils.decodePayload(""))
    }

    @Test
    fun `isExpired returns false for token with future exp`() {
        val futureExp = System.currentTimeMillis() / 1000 + 3600
        val jwt = createJwt(mapOf("exp" to futureExp))
        assertFalse(JwtUtils.isExpired(jwt))
    }

    @Test
    fun `isExpired returns true for token with past exp`() {
        val pastExp = System.currentTimeMillis() / 1000 - 3600
        val jwt = createJwt(mapOf("exp" to pastExp))
        assertTrue(JwtUtils.isExpired(jwt))
    }

    @Test
    fun `isExpired returns true within buffer window`() {
        val nearFutureExp = System.currentTimeMillis() / 1000 + 10
        val jwt = createJwt(mapOf("exp" to nearFutureExp))
        assertTrue(JwtUtils.isExpired(jwt, bufferSeconds = 30))
    }

    @Test
    fun `isExpired returns true for token without exp claim`() {
        val jwt = createJwt(mapOf("sub" to "user"))
        assertTrue(JwtUtils.isExpired(jwt))
    }

    @Test
    fun `isExpired returns true for invalid JWT`() {
        assertTrue(JwtUtils.isExpired("invalid"))
    }

    @Test
    fun `getType returns type claim`() {
        val jwt = createJwt(mapOf("type" to "account", "exp" to 9999999999L))
        assertEquals("account", JwtUtils.getType(jwt))
    }

    @Test
    fun `getType returns null when no type claim`() {
        val jwt = createJwt(mapOf("exp" to 9999999999L))
        assertNull(JwtUtils.getType(jwt))
    }
}

class TuistCredentialStoreTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `write and read credentials round-trip`() {
        val credDir = File(tempDir, "credentials")
        credDir.mkdirs()

        val hostname = "tuist.dev"
        val credFile = File(credDir, "$hostname.json")
        val credentials = TuistCredentials("access-token-123", "refresh-token-456")
        credFile.writeText(Gson().toJson(credentials))

        val read = Gson().fromJson(credFile.readText(), TuistCredentials::class.java)

        assertNotNull(read)
        assertEquals("access-token-123", read.accessToken)
        assertEquals("refresh-token-456", read.refreshToken)
    }

    @Test
    fun `credentials serialize with camelCase field names`() {
        val credentials = TuistCredentials("access", "refresh")
        val json = Gson().toJson(credentials)
        assertTrue(json.contains("\"accessToken\""))
        assertTrue(json.contains("\"refreshToken\""))
        assertFalse(json.contains("\"access_token\""))
        assertFalse(json.contains("\"refresh_token\""))
    }

    @Test
    fun `credentials deserialize from camelCase JSON`() {
        val json = """{"accessToken":"mytoken","refreshToken":"myrefresh"}"""
        val creds = Gson().fromJson(json, TuistCredentials::class.java)
        assertEquals("mytoken", creds.accessToken)
        assertEquals("myrefresh", creds.refreshToken)
    }

    @Test
    fun `credentials with null refreshToken`() {
        val json = """{"accessToken":"mytoken"}"""
        val creds = Gson().fromJson(json, TuistCredentials::class.java)
        assertEquals("mytoken", creds.accessToken)
        assertNull(creds.refreshToken)
    }
}
