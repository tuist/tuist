package dev.tuist.gradle

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ActorIdentifierTest {
    @Test fun `automatically resolves user and allows override and opt out`() {
        assertEquals("developer", ActorIdentifier.resolve(mapOf("USER" to "developer")))
        assertEquals("legacy-user", ActorIdentifier.resolve(mapOf("LOGNAME" to "legacy-user")))
        assertEquals("a".repeat(128), ActorIdentifier.resolve(mapOf("TUIST_ACTOR_ID" to "a".repeat(128))))
        assertEquals("windows-user", ActorIdentifier.resolve(mapOf("USERNAME" to "windows-user")))
        assertEquals("configured", ActorIdentifier.resolve(mapOf("USER" to "developer"), "configured"))
        assertEquals("employee-123", ActorIdentifier.resolve(mapOf("TUIST_ACTOR_ID" to "employee-123"), "configured"))
        assertNull(ActorIdentifier.resolve(mapOf("TUIST_ACTOR_ID" to "", "USER" to "developer")))
        assertNull(ActorIdentifier.resolve(mapOf("USER" to "developer"), ""))
    }

    @Test fun `unsafe and oversized overrides never fall back to a different identity`() {
        for (id in listOf("a\r\nb", "a b", "é", "a".repeat(129))) {
            assertNull(ActorIdentifier.resolve(mapOf("TUIST_ACTOR_ID" to id, "USER" to "developer")))
            assertNull(ActorIdentifier.resolve(mapOf("USER" to "developer"), id))
        }
    }
}
