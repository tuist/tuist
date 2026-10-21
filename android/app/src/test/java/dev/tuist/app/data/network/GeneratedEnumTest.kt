package dev.tuist.app.data.network

import com.squareup.moshi.Moshi
import dev.tuist.app.api.model.CreateMixBuildRequestDependencyCacheInner
import org.junit.Assert.assertEquals
import org.junit.Test

class GeneratedEnumTest {
    @Test
    fun `empty wire enum has a valid Kotlin name without changing JSON`() {
        val adapter = Moshi.Builder().build().adapter(CreateMixBuildRequestDependencyCacheInner.Reason::class.java)
        assertEquals("\"\"", adapter.toJson(CreateMixBuildRequestDependencyCacheInner.Reason.EMPTY))
        assertEquals(CreateMixBuildRequestDependencyCacheInner.Reason.EMPTY, adapter.fromJson("\"\""))
    }
}
