package dev.tuist.app.data.network

import dev.tuist.app.data.auth.TokenStorage
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import okhttp3.Interceptor
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class AuthInterceptorTest {

    private lateinit var tokenStorage: TokenStorage
    private lateinit var interceptor: AuthInterceptor

    @Before
    fun setUp() {
        tokenStorage = mockk()
        interceptor = AuthInterceptor(tokenStorage)
    }

    @Test
    fun `adds Authorization header when token exists`() {
        every { tokenStorage.getAccessToken() } returns "test-token"

        val request = Request.Builder().url("https://tuist.dev/api/projects").build()
        var capturedRequest: Request? = null

        val chain = mockk<Interceptor.Chain> {
            every { request() } returns request
            every { proceed(any()) } answers {
                capturedRequest = firstArg()
                Response.Builder()
                    .request(firstArg())
                    .protocol(Protocol.HTTP_1_1)
                    .code(200)
                    .message("OK")
                    .build()
            }
        }

        interceptor.intercept(chain)

        assertEquals("Bearer test-token", capturedRequest?.header("Authorization"))
    }

    @Test
    fun `does not add Authorization header when token is null`() {
        every { tokenStorage.getAccessToken() } returns null

        val request = Request.Builder().url("https://tuist.dev/api/projects").build()
        var capturedRequest: Request? = null

        val chain = mockk<Interceptor.Chain> {
            every { request() } returns request
            every { proceed(any()) } answers {
                capturedRequest = firstArg()
                Response.Builder()
                    .request(firstArg())
                    .protocol(Protocol.HTTP_1_1)
                    .code(200)
                    .message("OK")
                    .build()
            }
        }

        interceptor.intercept(chain)

        assertNull(capturedRequest?.header("Authorization"))
    }

    @Test
    fun `proceeds with the chain`() {
        every { tokenStorage.getAccessToken() } returns null

        val request = Request.Builder().url("https://tuist.dev/api/projects").build()
        val chain = mockk<Interceptor.Chain> {
            every { request() } returns request
            every { proceed(any()) } returns Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .build()
        }

        interceptor.intercept(chain)

        verify(exactly = 1) { chain.proceed(any()) }
    }
}
