package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ReportResponseCompatibilityTest {
    @Test
    fun `build and test responses accept absent null and future actor metadata`() {
        for (extra in listOf(
            "",
            ",\"actor\":null",
            ",\"actor\":{\"name\":\"opaque\",\"source\":\"future-source\",\"submission_auth\":\"future-auth\",\"future\":{}},\"future\":[1,2]"
        )) {
            val json = "{\"id\":\"server-id\"$extra}"
            assertEquals("server-id", Gson().fromJson(json, BuildReportResponse::class.java).id)
            val test = Gson().fromJson(json, TestResponse::class.java)
            assertEquals("server-id", test.id)
            assertNull(test.url)
        }
    }
}
