package dev.tuist.atlas

import android.net.Uri
import java.net.URI
import java.util.Locale

data class AtlasSection(
    val title: String,
    val description: String,
    val url: String,
    val screen: String,
    val id: String,
    val group: String,
    val shortcut: Boolean,
    val requiredScope: String,
) {
    fun destination(server: String): Uri {
        val origin = Uri.parse(server)
        return Uri
            .parse(url)
            .buildUpon()
            .scheme(origin.scheme)
            .encodedAuthority(origin.encodedAuthority)
            .build()
    }
}

data class AtlasGroup(
    val title: String,
    val description: String,
    val id: String,
    val parent: String,
    val placement: String,
)

data class AtlasDestinationCapability(
    val screen: String,
    val records: Boolean,
)

data class AtlasDestination(
    val screen: String,
    val recordId: String? = null,
) {
    // A navigation request only. Atlas authorizes the record when the destination loads it.
    data class Link(
        val destination: AtlasDestination,
        val server: String,
    )

    companion object {
        private const val PREFIX = "dev.tuist.atlas://navigate/"
        private val uuid = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

        // Classifies the intent so that invalid navigation links are reported instead of becoming OAuth callbacks.
        fun isNavigation(link: String): Boolean {
            val host = PREFIX.length - 1
            return link.regionMatches(0, PREFIX, 0, host, ignoreCase = true) && link.getOrNull(host).let { it == null || it in "/?#" }
        }

        // dev.tuist.atlas://navigate/<screen>[/<uuid>]?server=<https origin>. Anything else is rejected.
        fun parse(
            link: String,
            capabilities: List<AtlasDestinationCapability>,
        ): Link? {
            if (link.length > 2048 || !link.regionMatches(0, PREFIX, 0, PREFIX.length, ignoreCase = true)) return null
            val parts = link.substring(PREFIX.length).split('?')
            if (parts.size != 2 || '#' in parts[1] || !parts[1].startsWith("server=")) return null
            val segments = parts[0].split('/')
            if (segments.size > 2) return null
            val capability = capabilities.firstOrNull { it.screen == segments[0] } ?: return null
            val record = segments.getOrNull(1)
            if (record != null && (!capability.records || !uuid.matches(record))) return null
            val server = decode(parts[1].removePrefix("server="))?.let(::canonicalServer) ?: return null
            return Link(AtlasDestination(capability.screen, record), server)
        }

        // Returns https://<lowercase host>[:port]/, omitting the default port. java.net.URI validates hostnames
        // and IPv6 literals without DNS lookups; non-ASCII (non-punycode) hosts are rejected.
        fun canonicalServer(value: String): String? {
            if (value.any { it.code !in 33..126 } || '\\' in value || '%' in value) return null
            val uri = runCatching { URI(value) }.getOrNull() ?: return null
            val host = uri.host ?: return null
            if (!uri.scheme.equals("https", ignoreCase = true) || uri.rawUserInfo != null || uri.rawQuery != null ||
                uri.rawFragment != null || uri.rawPath !in listOf("", "/")
            ) {
                return null
            }
            val port = if (uri.port == -1) 443 else uri.port.takeIf { it in 1..65535 } ?: return null
            return "https://${host.lowercase(Locale.ROOT)}" + (if (port == 443) "" else ":$port") + "/"
        }

        private fun decode(value: String): String? {
            val bytes = java.io.ByteArrayOutputStream()
            var index = 0
            while (index < value.length) {
                val character = value[index]
                if (character == '%') {
                    val byte =
                        value
                            .substring(index + 1, minOf(index + 3, value.length))
                            .takeIf { it.length == 2 && it.all { digit -> digit in '0'..'9' || digit.lowercaseChar() in 'a'..'f' } }
                            ?.toInt(16)
                    if (byte == null || byte >= 0x80) return null
                    bytes.write(byte)
                    index += 3
                } else if (character.isLetterOrDigit() && character.code < 0x80 || character in "-._~:/[]") {
                    bytes.write(character.code)
                    index += 1
                } else {
                    return null
                }
            }
            return bytes.toString(Charsets.US_ASCII.name())
        }
    }
}

// Holds only the latest navigation request while a session is restored or signed in.
// Memory-only by design: a process death during sign-in drops it.
class AtlasDestinationRouter {
    sealed interface Outcome {
        data object None : Outcome

        data object WrongServer : Outcome

        data class Open(
            val destination: AtlasDestination,
        ) : Outcome
    }

    var pending: AtlasDestination.Link? = null
        private set
    private var signedIn = false

    fun receive(link: AtlasDestination.Link) {
        pending = link
    }

    fun resolve(server: String?): Outcome {
        if (server == null) {
            // A session that ended (sign-out or rejected credentials) discards links received for it.
            if (signedIn) reset()
            return Outcome.None
        }
        signedIn = true
        val link = pending ?: return Outcome.None
        pending = null
        return if (AtlasDestination.canonicalServer(server) == link.server) Outcome.Open(link.destination) else Outcome.WrongServer
    }

    fun reset() {
        pending = null
        signedIn = false
    }
}

class AtlasCore {
    private external fun sectionCount(): Int

    private external fun fieldLength(
        section: Int,
        field: Int,
    ): Int

    private external fun fieldByte(
        section: Int,
        field: Int,
        offset: Int,
    ): Int

    private external fun groupCount(): Int

    private external fun groupFieldLength(
        group: Int,
        field: Int,
    ): Int

    private external fun groupFieldByte(
        group: Int,
        field: Int,
        offset: Int,
    ): Int

    private external fun destinationCount(): Int

    private external fun destinationFieldLength(
        destination: Int,
        field: Int,
    ): Int

    private external fun destinationFieldByte(
        destination: Int,
        field: Int,
        offset: Int,
    ): Int

    fun sections(): List<AtlasSection> =
        List(sectionCount()) { section ->
            AtlasSection(
                readField(section, 0),
                readField(section, 1),
                readField(section, 2),
                readField(section, 3),
                readField(section, 4),
                readField(section, 5),
                readField(section, 6) == "1",
                readField(section, 7),
            )
        }

    fun groups(): List<AtlasGroup> =
        List(groupCount()) { group ->
            AtlasGroup(
                readField(group, 0, Table.GROUP),
                readField(group, 1, Table.GROUP),
                readField(group, 2, Table.GROUP),
                readField(group, 3, Table.GROUP),
                readField(group, 4, Table.GROUP),
            )
        }

    // Deep-link allowlist and record capability. Screen keys are frozen once shipped.
    fun destinations(): List<AtlasDestinationCapability> =
        List(destinationCount()) { destination ->
            val records = readField(destination, 1, Table.DESTINATION)
            check(records == "1" || records == "0") { "Invalid Atlas destination capability" }
            AtlasDestinationCapability(readField(destination, 0, Table.DESTINATION), records == "1")
        }

    private enum class Table { SECTION, GROUP, DESTINATION }

    private fun readField(
        index: Int,
        field: Int,
        table: Table = Table.SECTION,
    ): String {
        val length =
            when (table) {
                Table.SECTION -> fieldLength(index, field)
                Table.GROUP -> groupFieldLength(index, field)
                Table.DESTINATION -> destinationFieldLength(index, field)
            }
        check(length in 0..4096) { "Invalid Atlas core field length" }
        return ByteArray(length) { offset ->
            val byte =
                when (table) {
                    Table.SECTION -> fieldByte(index, field, offset)
                    Table.GROUP -> groupFieldByte(index, field, offset)
                    Table.DESTINATION -> destinationFieldByte(index, field, offset)
                }
            check(byte in 0..255) { "Invalid Atlas core field byte" }
            byte.toByte()
        }.toString(Charsets.UTF_8)
    }

    companion object {
        init {
            System.loadLibrary("atlas_core")
        }
    }
}
