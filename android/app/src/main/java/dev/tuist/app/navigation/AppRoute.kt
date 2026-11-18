package dev.tuist.app.navigation

import java.io.ByteArrayOutputStream
import java.net.URI
import java.net.URLEncoder
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.Locale

sealed interface AppRoute {
    data object Previews : AppRoute
    data object Profile : AppRoute
    data class PreviewDetail(
        val account: String,
        val project: String,
        val previewId: String,
        val server: String = DEFAULT_SERVER,
    ) : AppRoute

    fun toUrl(): String = when (this) {
        Previews -> "tuist://app/previews"
        Profile -> "tuist://app/profile"
        is PreviewDetail -> {
            val parts = listOf(account, project, "previews", previewId)
            require(parts.all(::validSegment) && previewId != "latest")
            "${serverBase(server)}/${parts.joinToString("/") { encode(it) }}"
        }
    }

    fun toHandoffUrl(): String = when (this) {
        Previews, Profile -> toUrl()
        is PreviewDetail -> {
            toUrl()
            val parts = listOf(account, project, "previews", previewId)
            "tuist://app/${parts.joinToString("/") { encode(it) }}?server=${encode(serverBase(server))}"
        }
    }

    companion object {
        const val DEFAULT_SERVER = "https://tuist.dev"

        /** Invalid and wrong-server links never produce a navigable route. */
        fun parse(url: String, currentServer: String): AppRoute? = runCatching {
            val uri = URI(url)
            require(!uri.isOpaque && uri.rawFragment == null && uri.rawUserInfo == null)
            if (uri.scheme.equals("tuist", ignoreCase = true)) {
                require(uri.rawAuthority.equals("app", ignoreCase = true) && uri.port == -1)
                val parts = pathSegments(uri.rawPath)
                when (parts) {
                    listOf("previews") -> { require(uri.rawQuery == null); Previews }
                    listOf("profile") -> { require(uri.rawQuery == null); Profile }
                    else -> {
                        require(parts.size == 4 && parts[2] == "previews" && parts[3] != "latest")
                        val server = uri.rawQuery?.let { query ->
                            require('&' !in query)
                            val pair = query.split("=")
                            require(pair.size == 2 && decode(pair[0]) == "server")
                            decode(pair[1])
                        } ?: DEFAULT_SERVER
                        val normalized = serverBase(server)
                        require(normalized == serverBase(currentServer))
                        PreviewDetail(parts[0], parts[1], parts[3], normalized)
                    }
                }
            } else {
                require(uri.rawQuery == null)
                val base = URI(serverBase(currentServer))
                require(origin(uri) == origin(base))
                val baseParts = if (base.rawPath.isNullOrEmpty()) emptyList() else pathSegments(base.rawPath)
                val parts = pathSegments(uri.rawPath)
                require(parts.take(baseParts.size) == baseParts)
                val detail = parts.drop(baseParts.size)
                require(detail.size == 4 && detail[2] == "previews" && detail[3] != "latest")
                PreviewDetail(detail[0], detail[1], detail[3], base.toASCIIString())
            }
        }.getOrNull()

        /** Legacy intent filters can also capture web-only pages and child resources. */
        fun isCurrentServerWebUrl(url: String, currentServer: String): Boolean = runCatching {
            val uri = URI(url)
            require(!uri.isOpaque && uri.rawUserInfo == null)
            val base = URI(serverBase(currentServer))
            require(origin(uri) == origin(base))
            val baseParts = if (base.rawPath.isNullOrEmpty()) emptyList() else pathSegments(base.rawPath)
            val path = uri.rawPath.orEmpty().trimEnd('/')
            val parts = if (path.isEmpty()) emptyList() else pathSegments(path)
            require(parts.take(baseParts.size) == baseParts)
            true
        }.getOrDefault(false)

        private fun serverBase(value: String): String {
            val uri = URI(value)
            require(!uri.isOpaque && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null)
            val origin = origin(uri)
            val path = uri.rawPath.orEmpty().trimEnd('/')
            val parts = if (path.isEmpty()) emptyList() else pathSegments(path)
            return origin + if (parts.isEmpty()) "" else "/" + parts.joinToString("/") { encode(it) }
        }

        private fun origin(uri: URI): String {
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            require(scheme == "https" || scheme == "http")
            val host = requireNotNull(uri.host).lowercase(Locale.ROOT)
            require(uri.rawUserInfo == null && (uri.port == -1 || uri.port in 1..65535))
            require(uri.port != -1 || uri.rawAuthority.equals(uri.host, ignoreCase = true))
            val defaultPort = if (scheme == "https") 443 else 80
            val port = uri.port.takeIf { it != -1 && it != defaultPort }
            return "$scheme://$host" + (port?.let { ":$it" } ?: "")
        }

        private fun pathSegments(path: String): List<String> {
            require(path.startsWith("/"))
            return path.substring(1).split("/").map { decode(it).also { part -> require(validSegment(part)) } }
        }

        private fun validSegment(value: String): Boolean = value.isNotEmpty() && value != "." && value != ".." &&
            value.none { it == '/' || it == '\\' || it.isWhitespace() || it.isISOControl() || Character.isSpaceChar(it) }

        private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
            .replace("+", "%20").replace("*", "%2A").replace("%7E", "~")

        private fun decode(value: String): String {
            val bytes = ByteArrayOutputStream()
            var offset = 0
            while (offset < value.length) {
                if (value[offset] == '%') {
                    require(offset + 2 < value.length)
                    bytes.write(value.substring(offset + 1, offset + 3).toInt(16))
                    offset += 3
                } else {
                    val end = value.indexOf('%', offset).let { if (it == -1) value.length else it }
                    bytes.write(value.substring(offset, end).toByteArray(Charsets.UTF_8))
                    offset = end
                }
            }
            return Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes.toByteArray())).toString()
        }
    }
}
