package dev.tuist.app.data.auth

import android.util.Base64
import dev.tuist.app.data.model.Account
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class JwtParserTest {

    private fun encodePayload(json: String): String {
        val encoded = Base64.encodeToString(
            json.toByteArray(),
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
        return "eyJhbGciOiJSUzI1NiJ9.$encoded.signature"
    }

    @Test
    fun `parseAccount returns Account for valid JWT`() {
        val jwt = encodePayload("""{"email":"user@test.com","preferred_username":"testuser"}""")

        val account = JwtParser.parseAccount(jwt)

        assertEquals(Account(email = "user@test.com", handle = "testuser"), account)
    }

    @Test
    fun `parseAccount returns null for JWT with wrong number of parts`() {
        assertNull(JwtParser.parseAccount("only.two"))
        assertNull(JwtParser.parseAccount("single"))
        assertNull(JwtParser.parseAccount("a.b.c.d"))
    }

    @Test
    fun `parseAccount returns null when email is missing`() {
        val jwt = encodePayload("""{"preferred_username":"testuser"}""")

        assertNull(JwtParser.parseAccount(jwt))
    }

    @Test
    fun `parseAccount returns null when preferred_username is missing`() {
        val jwt = encodePayload("""{"email":"user@test.com"}""")

        assertNull(JwtParser.parseAccount(jwt))
    }

    @Test
    fun `parseAccount returns null when email is empty`() {
        val jwt = encodePayload("""{"email":"","preferred_username":"testuser"}""")

        assertNull(JwtParser.parseAccount(jwt))
    }

    @Test
    fun `parseAccount returns null when preferred_username is empty`() {
        val jwt = encodePayload("""{"email":"user@test.com","preferred_username":""}""")

        assertNull(JwtParser.parseAccount(jwt))
    }

    @Test
    fun `parseAccount returns null for invalid base64 payload`() {
        assertNull(JwtParser.parseAccount("header.!!!invalid!!!.signature"))
    }

    @Test
    fun `parseAccount returns null for invalid JSON payload`() {
        val encoded = Base64.encodeToString(
            "not json".toByteArray(),
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
        val jwt = "header.$encoded.signature"

        assertNull(JwtParser.parseAccount(jwt))
    }
}
