package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class JwtParserTest {

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
        val payload = JwtParser.decodePayload(jwt)
        assertNotNull(payload)
        assertEquals("user123", payload["sub"])
    }

    @Test
    fun `decodePayload returns null for JWT with wrong number of parts`() {
        assertNull(JwtParser.decodePayload("only.two"))
        assertNull(JwtParser.decodePayload("single"))
        assertNull(JwtParser.decodePayload("a.b.c.d"))
        assertNull(JwtParser.decodePayload(""))
    }

    @Test
    fun `decodePayload returns null for invalid base64 payload`() {
        assertNull(JwtParser.decodePayload("header.!!!invalid!!!.signature"))
    }

    @Test
    fun `decodePayload returns null for invalid JSON payload`() {
        val encoded = Base64.getUrlEncoder().withoutPadding()
            .encodeToString("not json".toByteArray())
        assertNull(JwtParser.decodePayload("header.$encoded.signature"))
    }

    @Test
    fun `isExpired returns false for token with future exp`() {
        val futureExp = System.currentTimeMillis() / 1000 + 3600
        val jwt = createJwt(mapOf("exp" to futureExp))
        assertFalse(JwtParser.isExpired(jwt))
    }

    @Test
    fun `isExpired returns true for token with past exp`() {
        val pastExp = System.currentTimeMillis() / 1000 - 3600
        val jwt = createJwt(mapOf("exp" to pastExp))
        assertTrue(JwtParser.isExpired(jwt))
    }

    @Test
    fun `isExpired returns true within buffer window`() {
        val nearFutureExp = System.currentTimeMillis() / 1000 + 10
        val jwt = createJwt(mapOf("exp" to nearFutureExp))
        assertTrue(JwtParser.isExpired(jwt, bufferSeconds = 30))
    }

    @Test
    fun `isExpired returns true for token without exp claim`() {
        val jwt = createJwt(mapOf("sub" to "user"))
        assertTrue(JwtParser.isExpired(jwt))
    }

    @Test
    fun `isExpired returns true for invalid JWT`() {
        assertTrue(JwtParser.isExpired("invalid"))
    }

    @Test
    fun `getType returns type claim`() {
        val jwt = createJwt(mapOf("type" to "account", "exp" to 9999999999L))
        assertEquals("account", JwtParser.getType(jwt))
    }

    @Test
    fun `getType returns null when no type claim`() {
        val jwt = createJwt(mapOf("exp" to 9999999999L))
        assertNull(JwtParser.getType(jwt))
    }
}
