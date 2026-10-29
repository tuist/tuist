package dev.tuist.app.data

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class EnvironmentConfigTest {

    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun `setEnvironment persists synchronously before returning`() {
        // The environment switch kills the process right after setEnvironment returns, so a
        // write that would only land asynchronously (apply) is lost. Robolectric makes apply
        // synchronous, so drop it here to simulate the process dying first.
        val changed = EnvironmentConfig(ProcessDeathContext(context))
            .setEnvironment(TuistEnvironment.DEVELOPMENT)

        assertTrue(changed)
        assertEquals(TuistEnvironment.DEVELOPMENT, EnvironmentConfig(context).current)
    }

    @Test
    fun `setEnvironment returns false when already on the environment`() {
        EnvironmentConfig(context).setEnvironment(TuistEnvironment.STAGING)

        assertFalse(EnvironmentConfig(context).setEnvironment(TuistEnvironment.STAGING))
    }

    private class ProcessDeathContext(base: Context) : ContextWrapper(base) {
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
            ApplyDroppingPreferences(super.getSharedPreferences(name, mode))
    }

    private class ApplyDroppingPreferences(
        private val delegate: SharedPreferences,
    ) : SharedPreferences by delegate {
        override fun edit(): SharedPreferences.Editor = ApplyDroppingEditor(delegate.edit())
    }

    private class ApplyDroppingEditor(
        private val delegate: SharedPreferences.Editor,
    ) : SharedPreferences.Editor by delegate {
        override fun putString(key: String, value: String?) = also { delegate.putString(key, value) }
        override fun remove(key: String) = also { delegate.remove(key) }
        override fun clear() = also { delegate.clear() }
        override fun apply() = Unit
    }
}
