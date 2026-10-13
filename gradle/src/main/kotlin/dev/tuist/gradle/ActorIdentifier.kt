package dev.tuist.gradle

internal object ActorIdentifier {
    const val HEADER = "x-tuist-actor-id"

    fun resolve(environment: Map<String, String> = System.getenv(), override: String? = null): String? {
        val value = environment["TUIST_ACTOR_ID"] ?: override
            ?: listOf("USER", "USERNAME", "LOGNAME").firstNotNullOfOrNull { environment[it]?.takeIf(String::isNotEmpty) }
        return value?.takeIf { it.length in 1..128 && it.all { character -> character.code in 0x21..0x7e } }
    }
}
