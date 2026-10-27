package dev.tuist.kvmsmoke

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SmokeTest {
    @Test
    fun runsInsideTheAndroidGuest() {
        assertEquals("dev.tuist.kvmsmoke", InstrumentationRegistry.getInstrumentation().targetContext.packageName)
        assertEquals(34, android.os.Build.VERSION.SDK_INT)
        assertEquals("x86_64", android.os.Build.SUPPORTED_ABIS.first())
    }
}
