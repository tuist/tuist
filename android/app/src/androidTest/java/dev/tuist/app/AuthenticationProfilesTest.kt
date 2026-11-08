package dev.tuist.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.tuist.app.data.auth.TokenStorage
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Runs against a device-local OAuth/API fixture, never a live customer account or server. */
@RunWith(AndroidJUnit4::class)
class AuthenticationProfilesTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val tokens: TokenStorage get() = TokenStorage(context, dev.tuist.app.data.EnvironmentConfig(context))
    @Volatile private var oauthState: String? = null
    @Volatile private var oauthCookie: String? = null
    @Volatile private var browserHasCookie = false
    @Volatile private var rejectExchange = false
    private val jamAccounts = java.util.concurrent.CopyOnWriteArrayList<String>()
    private val previewAccounts = java.util.concurrent.CopyOnWriteArrayList<String>()
    private val membershipCalls = java.util.concurrent.atomic.AtomicInteger()

    /** Requires an actual old-APK sign-in and install -r, with its fixture API still running. Never seeds credentials. */
    @Test fun installedApkUpgradeRetainsLegacySession() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("profilePhase") == "installedUpgrade")
        val storage = tokens
        assertEquals(jwt("alice"), storage.getAccessToken())
        assertEquals("alice-refresh", storage.getRefreshToken())
        assertEquals(1, storage.profiles.value.size)
        val id = storage.snapshot().profileId!!
        assertEquals("http://localhost:8080", storage.credentials(id)!!.server)
        assertEquals(dev.tuist.app.data.TuistEnvironment.DEVELOPMENT.oauthClientId, storage.credentials(id)!!.clientId)
        val prefs = EncryptedSharedPreferences.create(context, "tuist_secure_prefs",
            MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
        assertFalse(prefs.contains("access_token"))
        assertFalse(prefs.contains("refresh_token"))
        val saved = org.json.JSONArray(prefs.getString("profiles_v1", null))
        assertEquals(1, saved.length())
        assertEquals(jwt("alice"), saved.getJSONObject(0).getString("access"))
        assertEquals("alice-refresh", saved.getJSONObject(0).getString("refresh"))
        assertFalse(File(context.applicationInfo.dataDir, "shared_prefs/tuist_secure_prefs.xml").readText().contains("alice-refresh"))
        ActivityScenario.launch(MainActivity::class.java).use {
            visible("Profile")
            click("Profile")
            visible("alice@example.invalid")
            screenshot("upgrade-retained-identity")
            chooser()
            assertTrue(device.hasObject(By.textContains("✓ alice@example.invalid")))
            assertEquals(1, device.findObjects(By.textContains("http://localhost:8080")).size)
            screenshot("upgrade-profile-chooser")
            click("Cancel")
            visible("Profile")
            click("Previews")
            visible("org-upgrade/app")
            screenshot("upgrade-authorized-previews")
            click("Jams")
            visible("alice")
            Thread.sleep(1500)
            click("Profile")
            visible("alice@example.invalid")
            assertEquals("alice-refresh", tokens.getRefreshToken())
            println("UPGRADE_PROOF profile=$id identity=alice@example.invalid origin=${storage.snapshot().origin} jams=alice access_matches_old=true refresh_matches_old=true legacy_keys_removed=true encrypted_on_disk=true")
        }
    }

    @Test fun migrationChooserAddCancelSwitchSignOutAndRecreate() {
        if (InstrumentationRegistry.getArguments().getString("profilePhase") == "origins") {
            verifyDistinctOrigins()
            return
        }
        if (InstrumentationRegistry.getArguments().getString("profilePhase") == "coldRestart") {
            verifyColdRestart()
            return
        }
        context.getSharedPreferences("tuist_environment", Context.MODE_PRIVATE).edit().putString("selected_environment", "DEVELOPMENT").commit()
        val prefs = EncryptedSharedPreferences.create(context, "tuist_secure_prefs",
            MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
        prefs.edit().clear().putString("access_token", jwt("alice")).putString("refresh_token", "alice-refresh").commit()
        context.getSharedPreferences("tuist_previews", Context.MODE_PRIVATE).edit().clear().commit()
        val server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                return when {
                    path.startsWith("/seed-browser-cookie") -> MockResponse()
                        .setHeader("Set-Cookie", "tuist_fixture_person=alice; Path=/; SameSite=Lax")
                        .setHeader("Content-Type", "text/html").setBody("<h1>Tuist fixture: Alice browser cookie set</h1>")
                    path.startsWith("/check-browser-cookie") -> {
                        browserHasCookie = request.getHeader("Cookie").orEmpty().contains("tuist_fixture_person=alice")
                        MockResponse().setHeader("Content-Type", "text/html").setBody("<h1>Tuist fixture: Alice cookie present = $browserHasCookie</h1>")
                    }
                    path.startsWith("/oauth2/authorize") -> {
                        oauthCookie = request.getHeader("Cookie")
                        oauthState = request.requestUrl!!.queryParameter("state")
                        MockResponse().setHeader("Content-Type", "text/html").setBody("<h1>Tuist test OAuth</h1>")
                    }
                    path == "/oauth2/token" && rejectExchange -> MockResponse().setResponseCode(503)
                    path == "/oauth2/token" -> MockResponse().setBody("""{"access_token":"${jwt("bob")}","refresh_token":"bob-refresh"}""")
                    path.contains("feature-flags") || path.contains("feature_flags") -> MockResponse().setBody("""{"enabled":["ai"]}""")
                    path == "/api/organizations" -> {
                        membershipCalls.incrementAndGet()
                        MockResponse().setResponseCode(500)
                    }
                    path == "/api/me/ai-subscriptions" -> MockResponse().setBody("""{"subscriptions":[]}""")
                    path.contains("/jams") && !path.contains("/socket") -> {
                        jamAccounts.add(path)
                        MockResponse().setBody("""{"jams":[],"cursor":null}""")
                    }
                    path.contains("/previews") -> {
                        previewAccounts.add(path)
                        MockResponse().setBody("""{"previews":[],"pagination_metadata":{"has_next_page":false,"has_previous_page":false,"page_size":10,"current_page":1}}""")
                    }
                    path == "/api/projects" -> MockResponse().setBody("""{"projects":[${listOf("alice", "bob", "org-a", "org-b", "shared").mapIndexed { index, name -> """{"id":$index,"full_name":"$name/app","default_branch":"main","visibility":"private"}""" }.joinToString()}]}""")
                    else -> MockResponse().setResponseCode(404).setBody("{}")
                }
            }
        }
        server.start(8080)
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                visible("Profile")
                scenario.onActivity {
                    androidx.browser.customtabs.CustomTabsIntent.Builder().build().launchUrl(it, Uri.parse("http://localhost:8080/seed-browser-cookie"))
                }
                Thread.sleep(2000)
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("http://localhost:8080/check-browser-cookie")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                val cookieDeadline = System.currentTimeMillis() + 10_000
                while (!browserHasCookie && System.currentTimeMillis() < cookieDeadline) Thread.sleep(100)
                assertTrue("Ordinary browser session retains Alice cookie", browserHasCookie)
                context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
                visible("Profile")
                assertEquals("alice-refresh", tokens.getRefreshToken())
                assertFalse(File(context.applicationInfo.dataDir, "shared_prefs/tuist_secure_prefs.xml").readText().contains("alice-refresh"))
                click("Jams")
                assertFalse(device.hasObject(By.desc("Switch account")))
                chooser()
                assertFalse(device.hasObject(By.text("Workspaces for this login")))
                assertTrue(device.hasObject(By.textContains("✓ alice@example.invalid")))
                screenshot("00-personal-upgrade-fallback")
                click("Cancel")
                assertJamsAccount("alice")
                click("Profile")
                visible("alice@example.invalid")
                screenshot("01-legacy-profile")
                chooser()
                screenshot("02-profile-long-press")
                click("Add login profile")
                visible("Welcome to Tuist")
                screenshot("03-reused-login")
                click("Cancel")
                visible("alice@example.invalid")
                assertEquals(1, tokens.profiles.value.size)

                chooser()
                click("Add login profile")
                rejectExchange = true
                authorize()
                visible("Welcome to Tuist")
                assertEquals("alice-refresh", tokens.getRefreshToken())
                screenshot("04-failed-add-retains-session")
                click("Cancel")
                chooser()
                click("Add login profile")
                rejectExchange = false
                authorize()
                visible("Profile")
                click("Profile")
                visible("bob@example.invalid")
                assertEquals(2, tokens.profiles.value.size)
                screenshot("05-added-second-profile")
                assertJamsAccount("bob")
                assertProjects("alice/app", "org-b/app", "org-a/app")

                chooser()
                assertTrue(device.hasObject(By.textContains("alice@example.invalid\n")))
                assertTrue(device.hasObject(By.textContains("✓ bob@example.invalid\n")))
                assertFalse(device.hasObject(By.textContains("shared\n")))
                assertEquals(2, device.findObjects(By.textContains("http://localhost:8080")).size)
                screenshot("06-saved-profiles-only")
                device.findObject(By.textContains("alice@example.invalid\n")).click()
                visible("Profile")
                click("Profile")
                visible("alice@example.invalid")
                screenshot("07-switched-to-legacy")
                assertJamsAccount("alice")
                assertProjects("alice/app", "org-a/app", "shared/app")
                screenshot("07b-cross-organization-previews-retain-alice")
                scenario.recreate()
                visible("Profile")
                click("Profile")
                visible("alice@example.invalid")
                assertEquals("alice-refresh", TokenStorage(context, dev.tuist.app.data.EnvironmentConfig(context)).getRefreshToken())
                screenshot("08-recreated-selection")
                click("Sign out")
                visible("Profile")
                click("Profile")
                visible("bob@example.invalid")
                assertEquals(1, tokens.profiles.value.size)
                screenshot("09-sign-out-removes-only-active")
                assertJamsAccount("bob")
                assertEquals("Profile workflows never discover memberships", 0, membershipCalls.get())
            }
        } finally { server.shutdown() }
    }

    private fun verifyDistinctOrigins() {
        context.getSharedPreferences("tuist_environment", Context.MODE_PRIVATE).edit().putString("selected_environment", "DEVELOPMENT").commit()
        val prefs = EncryptedSharedPreferences.create(context, "tuist_secure_prefs",
            MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
        val fixtureProfiles = org.json.JSONArray()
        listOf("alice" to 8080, "bob" to 8081).forEach { (person, port) ->
            fixtureProfiles.put(org.json.JSONObject().put("id", person).put("server", "http://localhost:$port")
                .put("access", jwt(person)).put("refresh", "$person-refresh").put("client_id", "fixture-client-$port")
                .put("organization", "shared").put("memberships", org.json.JSONArray(listOf("shared"))))
        }
        prefs.edit().clear().putString("profiles_v1", fixtureProfiles.toString()).putString("active_profile", "alice")
            .putString("active_organization", "shared").commit()
        context.getSharedPreferences("tuist_previews", Context.MODE_PRIVATE).edit().clear().commit()
        val first = MockWebServer()
        val other = MockWebServer()
        val otherCalls = java.util.concurrent.CopyOnWriteArrayList<String>()
        fun dispatcher(person: String, project: String) = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                assertEquals("Bearer ${jwt(person)}", request.getHeader("Authorization"))
                if (person == "bob") otherCalls.add(path)
                return when {
                    path == "/api/organizations" -> {
                        membershipCalls.incrementAndGet()
                        MockResponse().setResponseCode(500)
                    }
                    path.contains("feature-flags") || path.contains("feature_flags") -> MockResponse().setBody("""{"enabled":["ai"]}""")
                    path == "/api/projects" -> MockResponse().setBody("""{"projects":[{"id":1,"full_name":"shared/$project","default_branch":"main","visibility":"private"},{"id":2,"full_name":"other-org/$project","default_branch":"main","visibility":"private"}]}""")
                    path.contains("/previews") -> {
                        previewAccounts.add(path)
                        MockResponse().setBody("""{"previews":[],"pagination_metadata":{"has_next_page":false,"has_previous_page":false,"page_size":10}}""")
                    }
                    path.contains("/jams") && !path.contains("/socket") -> {
                        jamAccounts.add(path)
                        MockResponse().setBody("""{"jams":[]}""")
                    }
                    path == "/api/me/ai-subscriptions" -> MockResponse().setBody("""{"subscriptions":[]}""")
                    else -> MockResponse().setResponseCode(404)
                }
            }
        }
        first.dispatcher = dispatcher("alice", "first-origin")
        other.dispatcher = dispatcher("bob", "other-origin")
        first.start(8080)
        other.start(8081)
        try {
            ActivityScenario.launch(MainActivity::class.java).use {
                visible("shared/first-origin")
                chooser()
                assertTrue(device.hasObject(By.textContains("http://localhost:8080")))
                assertTrue(device.hasObject(By.textContains("http://localhost:8081")))
                assertTrue(device.hasObject(By.textContains("✓ alice@example.invalid")))
                assertTrue(device.hasObject(By.textContains("bob@example.invalid")))
                assertFalse(device.hasObject(By.textContains("shared\n")))
                screenshot("12-saved-profiles-distinct-origins")
                device.findObject(By.textContains("http://localhost:8081")).click()
                visible("shared/other-origin")
                assertEquals("http://localhost:8081", tokens.snapshot().origin)
                screenshot("13-selected-other-origin-previews")
                assertProjects("shared/other-origin", "other-org/other-origin", "shared/other-origin")
                assertJamsAccount("bob")
                assertTrue(otherCalls.any { it.contains("/api/accounts/bob/jams") })
                assertTrue(otherCalls.any { it.contains("/api/projects/shared/other-origin/previews") })
                screenshot("14-selected-other-origin-login-identity")
                chooser()
                assertTrue(device.hasObject(By.textContains("✓ bob@example.invalid")))
                screenshot("15-active-profile-after-switch")
                click("Cancel")
                assertEquals("Startup, chooser and switching never discover memberships", 0, membershipCalls.get())
            }
        } finally { first.shutdown(); other.shutdown() }
    }

    private fun verifyColdRestart() {
        assertEquals("bob@example.invalid", tokens.profiles.value.single().label)
        val server = MockWebServer()
        val previews = java.util.concurrent.CopyOnWriteArrayList<String>()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                return when {
                    path == "/api/organizations" -> {
                        membershipCalls.incrementAndGet()
                        MockResponse().setResponseCode(500)
                    }
                    path.contains("feature-flags") || path.contains("feature_flags") -> MockResponse().setBody("""{"enabled":["ai"]}""")
                    path == "/api/projects" -> MockResponse().setBody("""{"projects":[{"id":1,"full_name":"bob/personal","default_branch":"main","visibility":"private"},{"id":2,"full_name":"org-b/app","default_branch":"main","visibility":"private"}]}""")
                    path.contains("/previews") -> {
                        previews.add(path)
                        MockResponse().setBody("""{"previews":[],"pagination_metadata":{"has_next_page":false,"has_previous_page":false,"page_size":10}}""")
                    }
                    path.contains("/jams") && !path.contains("/socket") -> {
                        jamAccounts.add(path)
                        MockResponse().setBody("""{"jams":[]}""")
                    }
                    path == "/api/me/ai-subscriptions" -> MockResponse().setBody("""{"subscriptions":[]}""")
                    else -> MockResponse().setResponseCode(404)
                }
            }
        }
        server.start(8080)
        try {
            ActivityScenario.launch(MainActivity::class.java).use {
                visible("org-b/app")
                assertTrue(previews.isNotEmpty())
                assertTrue("First previews after process restart use the profile's saved project: $previews", previews.all { it.contains("/projects/org-b/") })
                click("org-b/app")
                visible("bob/personal")
                device.pressBack()
                screenshot("10-cold-process-restart-saved-project")
                assertJamsAccount("bob")
                chooser()
                assertTrue(device.hasObject(By.textContains("✓ bob@example.invalid")))
                click("Cancel")
                screenshot("11-cold-restart-login-identity")
                assertEquals("Cold restart never discovers memberships", 0, membershipCalls.get())
            }
        } finally { server.shutdown() }
    }

    private fun assertJamsAccount(login: String) {
        click("Profile")
        visible("$login@example.invalid")
        jamAccounts.clear()
        click("Jams")
        val deadline = System.currentTimeMillis() + 10_000
        while (jamAccounts.isEmpty() && System.currentTimeMillis() < deadline) Thread.sleep(100)
        assertTrue("Jams default to the saved personal identity: $jamAccounts", jamAccounts.isNotEmpty() && jamAccounts.all { it.contains("/accounts/$login/jams") })
        click("Profile")
        visible("$login@example.invalid")
    }

    private fun assertProjects(current: String, selected: String, alternative: String) {
        previewAccounts.clear()
        click("Previews")
        click(current)
        visible(alternative)
        visible(selected)
        screenshot("projects-cross-organization-picker-${selected.substringBefore('/')}")
        click(selected)
        visible(selected)
        val deadline = System.currentTimeMillis() + 10_000
        while (previewAccounts.none { it.contains("/projects/$selected/previews") } && System.currentTimeMillis() < deadline) Thread.sleep(100)
        assertTrue("Previews use the selected authorized project: $previewAccounts", previewAccounts.any { it.contains("/projects/$selected/previews") })
        screenshot("projects-${selected.substringBefore('/')}")
        click("Profile")
    }

    private fun authorize() {
        oauthState = null
        click("Sign in with Tuist")
        val deadline = System.currentTimeMillis() + 10_000
        while (oauthState == null && System.currentTimeMillis() < deadline) Thread.sleep(100)
        assertNotNull("Browser reached device-local OAuth fixture", oauthState)
        assertFalse("Ephemeral add must not send Alice browser cookie", oauthCookie.orEmpty().contains("tuist_fixture_person"))
        context.startActivity(Intent(context, MainActivity::class.java).setData(Uri.parse("tuist://oauth-callback?code=fixture&state=$oauthState"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        Thread.sleep(1500)
    }

    private fun chooser() {
        visible("Profile")
        device.findObject(By.text("Profile")).longClick()
        visible("Profiles")
        visible("Add login profile")
    }
    private fun click(text: String) {
        repeat(3) {
            visible(text)
            try {
                device.findObject(By.text(text)).click()
                device.waitForIdle()
                return
            } catch (_: androidx.test.uiautomator.StaleObjectException) {
                Thread.sleep(100)
            }
        }
        fail("Could not click stable element: $text")
    }
    private fun visible(text: String) { assertTrue("Visible: $text", device.wait(Until.hasObject(By.text(text)), 10_000)) }
    private fun screenshot(name: String) {
        val directory = File(context.getExternalFilesDir(null), "profile-evidence").apply { mkdirs() }
        device.takeScreenshot(File(directory, "$name.png"))
        Thread.sleep(600)
    }
    private fun jwt(subject: String): String {
        val payload = """{"sub":"$subject","email":"$subject@example.invalid","preferred_username":"$subject"}"""
        return "header.${Base64.encodeToString(payload.toByteArray(), Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)}.fixture"
    }
}
