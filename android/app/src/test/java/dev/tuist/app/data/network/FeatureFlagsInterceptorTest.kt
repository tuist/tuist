package dev.tuist.app.data.network

import io.mockk.every
import io.mockk.mockk
import okhttp3.Interceptor
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FeatureFlagsInterceptorTest {

    @Test
    fun `adds feature flag header when TUIST feature variables exist`() {
        val interceptor = FeatureFlagsInterceptor(
            mapOf(
                "TUIST_FEATURE_FLAG_B" to "enabled",
                "TUIST_FEATURE_FLAG_A" to "1",
            )
        )
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

        assertEquals("A,B", capturedRequest?.header(FeatureFlagsHeaders.HEADER_NAME))
    }

    @Test
    fun `does not add feature flag header when no TUIST feature variables exist`() {
        val interceptor = FeatureFlagsInterceptor(mapOf("TUIST_TOKEN" to "token"))
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

        assertNull(capturedRequest?.header(FeatureFlagsHeaders.HEADER_NAME))
    }

    @Test
    fun `replaces any existing feature flag header with the current environment values`() {
        val interceptor = FeatureFlagsInterceptor(mapOf("TUIST_FEATURE_FLAG_A" to "1"))
        val request = Request.Builder()
            .url("https://tuist.dev/api/projects")
            .header(FeatureFlagsHeaders.HEADER_NAME, "OLD")
            .build()
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

        assertEquals("A", capturedRequest?.header(FeatureFlagsHeaders.HEADER_NAME))
    }
}
