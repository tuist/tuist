package dev.tuist.app.data.auth

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class TokenStorageTest {
    private val prefs = RuntimeEnvironment.getApplication().getSharedPreferences("profile-test", Context.MODE_PRIVATE)
    private val server = "https://tuist.dev"

    @Before fun clear() { prefs.edit().clear().commit() }

    @Test fun `legacy migration is additive and survives restart without signing out`() {
        prefs.edit().putString("access_token", jwt("alice")).putString("refresh_token", "legacy-refresh").commit()
        val storage = TokenStorage(prefs, server)
        assertEquals(jwt("alice"), storage.getAccessToken())
        assertEquals("legacy-refresh", storage.getRefreshToken())
        val id = storage.snapshot().profileId
        val restarted = TokenStorage(prefs, server)
        assertEquals(id, restarted.snapshot().profileId)
        assertEquals(jwt("alice"), restarted.getAccessToken())
        assertEquals(1, restarted.profiles.value.size)
        assertFalse(prefs.contains("access_token"))
    }

    @Test fun `same server users stay distinct and switching persists the selection`() {
        val storage = TokenStorage(prefs, server)
        storage.storeTokens(jwt("alice"), "alice-refresh")
        val alice = storage.snapshot().profileId!!
        storage.storeTokens(jwt("bob"), "bob-refresh")
        assertEquals(2, storage.profiles.value.size)
        storage.switchProfile(alice)
        assertEquals("alice-refresh", TokenStorage(prefs, server).getRefreshToken())
        assertEquals(alice, TokenStorage(prefs, server).snapshot().profileId)
    }

    @Test fun `rotation preserves profile identity and never updates another session`() {
        val storage = TokenStorage(prefs, server)
        storage.storeTokens(jwt("alice"), "alice-refresh")
        val alice = storage.snapshot()
        assertTrue(storage.rotate(alice, "alice-refresh", jwt("alice", "rotated"), "new-refresh"))
        assertEquals(alice, storage.snapshot())
        assertFalse(storage.rotate(alice, "alice-refresh", jwt("alice"), "stale-refresh"))
        storage.storeTokens(jwt("bob"), "bob-refresh")
        val bob = storage.snapshot()
        assertTrue(storage.rotate(alice, "new-refresh", jwt("alice"), "late-refresh"))
        assertEquals(bob, storage.snapshot())
        assertEquals("bob-refresh", storage.getRefreshToken())
        assertFalse(storage.clearIfCurrent(alice))
        storage.switchProfile(alice.profileId!!)
        assertFalse(storage.rotate(alice, "new-refresh", jwt("alice"), "aba-refresh"))
        assertEquals("late-refresh", TokenStorage(prefs, server).getRefreshToken())
    }

    @Test fun `false migration commit preserves legacy credentials and usable session for retry`() {
        prefs.edit().putString("access_token", jwt("alice")).putString("refresh_token", "legacy-refresh").commit()
        val previous = prefs.all.toMap()
        val failing = FailingPreferences(prefs).apply { failNextCommit = true }
        val storage = TokenStorage(failing, server)
        assertEquals(previous, prefs.all)
        assertEquals(jwt("alice"), storage.getAccessToken())
        assertEquals("legacy-refresh", storage.getRefreshToken())
        assertEquals("legacy-refresh", TokenStorage(prefs, server).getRefreshToken())
        assertFalse(prefs.contains("access_token"))
    }

    @Test fun `false commits roll back local changes but retain spent token rotations in memory`() {
        val failing = FailingPreferences(prefs)
        val storage = TokenStorage(failing, server)
        storage.storeTokens(jwt("alice"), "alice-refresh")
        val alice = storage.snapshot().profileId!!
        storage.storeTokens(jwt("bob"), "bob-refresh")
        val session = storage.snapshot()
        val profiles = storage.profiles.value
        val previous = prefs.all.toMap()
        val operations: List<() -> Unit> = listOf(
            { storage.storeTokens(jwt("charlie"), "charlie-refresh") },
            { storage.switchProfile(alice) },
            { storage.clear() },
            { storage.selectOrganization(session.profileId!!, "organization") },
            { storage.updateMemberships(session.profileId!!, listOf("organization")) },
        )
        operations.forEach { operation ->
            failing.failNextCommit = true
            assertThrows(IllegalStateException::class.java) { operation() }
            assertEquals(previous, prefs.all)
            assertEquals(session, storage.snapshot())
            assertEquals(profiles, storage.profiles.value)
            assertEquals(jwt("bob"), storage.accessTokenFlow.value)
            assertEquals("bob-refresh", storage.getRefreshToken())
            assertEquals(session.profileId, TokenStorage(prefs, server).snapshot().profileId)
        }
        failing.failNextCommit = true
        assertFalse(storage.rotate(session, "bob-refresh", jwt("bob", "rotated"), "rotated-refresh"))
        assertEquals(previous, prefs.all)
        assertEquals(session, storage.snapshot())
        assertEquals("rotated-refresh", storage.getRefreshToken())
        assertEquals("bob-refresh", TokenStorage(prefs, server).getRefreshToken())
        assertTrue(storage.retryPendingRotation())
        assertEquals("rotated-refresh", TokenStorage(prefs, server).getRefreshToken())
    }

    @Test fun `failed inactive rotations survive A B and A B A without resurrecting removed profiles`() {
        listOf(false, true).forEach { switchBack ->
            prefs.edit().clear().commit()
            val failing = FailingPreferences(prefs)
            val storage = TokenStorage(failing, server)
            storage.storeTokens(jwt("alice"), "alice-refresh")
            val alice = storage.snapshot()
            storage.storeTokens(jwt("bob"), "bob-refresh")
            if (switchBack) storage.switchProfile(alice.profileId!!)
            failing.failNextCommit = true
            assertFalse(storage.rotate(alice, "alice-refresh", jwt("alice", "new"), "new-refresh"))
            assertEquals("new-refresh", storage.credentials(alice.profileId!!)!!.refresh)
            storage.switchProfile(alice.profileId)
            assertTrue(storage.retryPendingRotation())
            assertEquals("new-refresh", TokenStorage(prefs, server).getRefreshToken())
            storage.clear()
            assertFalse(storage.rotate(alice, "new-refresh", jwt("alice"), "resurrected"))
            assertTrue(storage.retryPendingRotation())
            assertNull(storage.credentials(alice.profileId))
        }
    }

    @Test fun `sign out with fallback is one durable transaction and failure retains outgoing login`() {
        val failing = FailingPreferences(prefs)
        val storage = TokenStorage(failing, server)
        storage.storeTokens(jwt("alice"), "alice-refresh")
        storage.storeTokens(jwt("bob"), "bob-refresh")
        val before = storage.snapshot()
        failing.failNextCommit = true
        assertThrows(IllegalStateException::class.java) { storage.clear(selectFallback = true) }
        assertEquals(before, storage.snapshot())
        assertEquals("bob-refresh", TokenStorage(prefs, server).getRefreshToken())
        storage.clear(selectFallback = true)
        assertEquals("alice-refresh", TokenStorage(prefs, server).getRefreshToken())
        failing.failNextCommit = true
        assertThrows(IllegalStateException::class.java) { storage.clear(selectFallback = true) }
        assertEquals("alice-refresh", TokenStorage(prefs, server).getRefreshToken())
    }

    private class FailingPreferences(private val delegate: SharedPreferences) : SharedPreferences by delegate {
        var failNextCommit = false
        override fun edit(): SharedPreferences.Editor {
            val editor = delegate.edit()
            return object : SharedPreferences.Editor by editor {
                override fun putString(key: String?, value: String?): SharedPreferences.Editor {
                    editor.putString(key, value)
                    return this
                }
                override fun remove(key: String?): SharedPreferences.Editor {
                    editor.remove(key)
                    return this
                }
                override fun commit(): Boolean {
                    val result = editor.commit()
                    if (!failNextCommit) return result
                    failNextCommit = false
                    return false
                }
            }
        }
    }

    @Test fun `sign out removes only active profile and does not resurrect legacy credentials`() {
        val storage = TokenStorage(prefs, server)
        storage.storeTokens(jwt("alice"), "alice-refresh")
        val alice = storage.snapshot().profileId!!
        storage.storeTokens(jwt("bob"), "bob-refresh")
        storage.clear()
        val restarted = TokenStorage(prefs, server)
        assertNull(restarted.getAccessToken())
        assertEquals(listOf(alice), restarted.profiles.value.map { it.id })
    }

    @Test fun `origins retain separate credentials and global selection survives restart`() {
        val storage = TokenStorage(prefs, server)
        storage.storeTokens(jwt("alice"), "first")
        val id = storage.snapshot().profileId
        storage.storeTokens(jwt("alice", "new"), "second")
        assertEquals(id, storage.snapshot().profileId)
        assertEquals(1, storage.profiles.value.size)
        val staging = TokenStorage(prefs, "https://staging.tuist.dev")
        assertEquals("second", staging.getRefreshToken())
        staging.storeTokens(jwt("alice"), "staging")
        val restarted = TokenStorage(prefs, server)
        assertEquals(2, restarted.profiles.value.size)
        assertEquals("https://staging.tuist.dev", restarted.selectedServer())
        restarted.selectOrganization(id!!, "tuist")
        val selected = restarted.snapshot()
        assertEquals("second", restarted.getRefreshToken())
        assertEquals("tuist", restarted.selectedAccount())
        val again = TokenStorage(prefs, server)
        assertEquals("tuist", again.snapshot().organization)
        assertEquals(server, again.snapshot().origin)
        assertEquals(selected.profileId, again.snapshot().profileId)
        assertTrue(restarted.rotate(selected, "second", jwt("alice", "rotated"), "third"))
        assertEquals("tuist", restarted.snapshot().organization)
    }

    private fun jwt(subject: String, nonce: String = "initial"): String {
        val payload = """{"sub":"$subject","email":"$subject@example.invalid","preferred_username":"$subject","nonce":"$nonce"}"""
        return "header.${Base64.encodeToString(payload.toByteArray(), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)}.signature"
    }
}
