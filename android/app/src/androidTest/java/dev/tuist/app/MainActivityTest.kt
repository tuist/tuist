package dev.tuist.app

import android.content.Context
import android.util.Base64
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tuist.app.api.FeatureFlagsApi
import dev.tuist.app.api.model.FeatureFlags1
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.auth.TokenStorage
import dev.tuist.app.data.featureflags.FeatureFlag
import dev.tuist.app.data.featureflags.FeatureFlagsRepository
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import retrofit2.Response
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class MainActivityTest {
    @Test
    fun offlineForegroundRetainsFlagsButChangingLoginClearsThem() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val prefs = context.getSharedPreferences("foreground-flags-test", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        val tokens = TokenStorage(prefs, "https://flags.example.invalid")
        fun jwt(person: String): String {
            val payload = """{"sub":"$person","email":"$person@example.invalid","preferred_username":"$person"}"""
            return "header.${Base64.encodeToString(payload.toByteArray(), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)}.signature"
        }
        tokens.storeTokens(jwt("alice"), "alice-refresh")
        val requests = AtomicInteger()
        // Seed through the same repository's public refresh contract, then make its transport offline.
        var offline = false
        val repository = FeatureFlagsRepository(object : FeatureFlagsApi {
            override suspend fun listFeatureFlags(): Response<FeatureFlags1> {
                requests.incrementAndGet()
                if (offline) throw IOException("offline foreground")
                return Response.success(FeatureFlags1(listOf("ai")))
            }
        })
        runBlocking {
            repository.refresh(AuthState.LoggedIn(Account("alice@example.invalid", "alice")), tokens.snapshot())
        }
        offline = true
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { activity ->
                activity.authRepository = AuthRepository(tokens, OkHttpClient(), activity.environmentConfig, activity.pushRegistrationManager)
                activity.featureFlags = repository
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            instrumentation.waitForIdleSync()
            assertTrue(requests.get() >= 2)
            assertEquals(setOf(FeatureFlag.AI), repository.enabled.value)
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.moveToState(Lifecycle.State.RESUMED)
            instrumentation.waitForIdleSync()
            assertEquals(setOf(FeatureFlag.AI), repository.enabled.value)
            scenario.onActivity { tokens.storeTokens(jwt("bob"), "bob-refresh") }
            instrumentation.waitForIdleSync()
            assertEquals(emptySet<FeatureFlag>(), repository.enabled.value)
        }
        prefs.edit().clear().commit()
    }

    @Test
    fun normalLaunchAndForegroundReturnKeepTheAppVisible() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            instrumentation.waitForIdleSync()
            scenario.onActivity { assertTrue(it.window.decorView.isShown) }
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.moveToState(Lifecycle.State.RESUMED)
            instrumentation.waitForIdleSync()
            scenario.onActivity { assertTrue(it.window.decorView.isShown) }
        }
    }
}
