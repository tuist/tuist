package dev.tuist.guild

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ProtocolException
import java.net.Socket
import java.net.URI
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * A minimal RFC 6455 client for the core's presence socket: the platform SDK has
 * none, and the app avoids extra dependencies. It sends text frames, buffers the
 * text messages it receives on a background thread, and answers pings.
 */
class WebSocket private constructor(private val socket: Socket, input: InputStream, private val output: OutputStream) {
    private val frames = ArrayList<String>()
    @Volatile private var closed = false

    init {
        Thread({ receive(DataInputStream(input)) }, "LuftWebSocket").apply { isDaemon = true }.start()
    }

    fun send(text: String) {
        if (closed) throw IOException("closed")
        write(OPCODE_TEXT, text.toByteArray(Charsets.UTF_8))
    }

    /** The text messages received since the last read, without blocking, and whether the connection has closed. */
    fun read(): Pair<List<String>, Boolean> = synchronized(frames) {
        val received = frames.toList()
        frames.clear()
        received to closed
    }

    fun close() {
        if (!closed) try { write(OPCODE_CLOSE, byteArrayOf(0x03, 0xE8.toByte())) } catch (_: IOException) { }
        closed = true
        try { socket.close() } catch (_: IOException) { }
    }

    private fun write(opcode: Int, payload: ByteArray) = synchronized(output) {
        val mask = ByteArray(4).also(random::nextBytes)
        output.write(encode(opcode, payload, mask))
        output.flush()
    }

    private fun receive(input: DataInputStream) {
        try {
            var message: ByteArrayOutputStream? = null
            var text = false
            while (!closed) {
                val frame = decode(input, MAX_MESSAGE)
                when (frame.opcode) {
                    OPCODE_CONTINUATION, OPCODE_TEXT, OPCODE_BINARY -> {
                        if ((frame.opcode == OPCODE_CONTINUATION) != (message != null)) throw ProtocolException("fragment")
                        if (message == null) { message = ByteArrayOutputStream(); text = frame.opcode == OPCODE_TEXT }
                        if (message.size() + frame.payload.size > MAX_MESSAGE) throw ProtocolException("too large")
                        message.write(frame.payload)
                        if (frame.fin) {
                            // Binary messages are not part of the protocol; they are dropped.
                            if (text) synchronized(frames) {
                                if (frames.size >= MAX_PENDING) throw ProtocolException("unread")
                                frames.add(message.toString("UTF-8"))
                            }
                            message = null
                        }
                    }
                    OPCODE_PING -> write(OPCODE_PONG, frame.payload)
                    OPCODE_PONG -> {}
                    OPCODE_CLOSE -> {
                        if (!closed) write(OPCODE_CLOSE, frame.payload.copyOf(minOf(2, frame.payload.size)))
                        break
                    }
                    else -> throw ProtocolException("opcode")
                }
            }
        } catch (_: Exception) {
        } finally {
            closed = true
            try { socket.close() } catch (_: IOException) { }
        }
    }

    class Frame(val fin: Boolean, val opcode: Int, val payload: ByteArray)

    companion object {
        const val OPCODE_CONTINUATION = 0x0
        const val OPCODE_TEXT = 0x1
        const val OPCODE_BINARY = 0x2
        const val OPCODE_CLOSE = 0x8
        const val OPCODE_PING = 0x9
        const val OPCODE_PONG = 0xA
        /** The largest message accepted, across its frames; presence states are far smaller. */
        const val MAX_MESSAGE = 1 shl 20
        /** Messages left unread before the connection is dropped; the core reads every few seconds. */
        private const val MAX_PENDING = 1024
        private const val TIMEOUT = 10_000
        // Phoenix answers heartbeats every 25 s; a longer silence means the connection is gone.
        private const val READ_TIMEOUT = 75_000
        private const val GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        private val random = SecureRandom()
        private val token = Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")

        /**
         * Opens `wss://` with the platform's TLS, or plain `ws://` to a loopback
         * host. `protocols` carry the bearer credential: they never appear in errors.
         */
        fun connect(url: String, protocols: List<String>): WebSocket {
            val uri = URI(url)
            val host = uri.host ?: throw IOException("host")
            val secure = uri.scheme == "wss"
            require((secure || (uri.scheme == "ws" && host in setOf("localhost", "127.0.0.1", "[::1]"))) && uri.rawUserInfo == null)
            require(protocols.all { token.matches(it) })
            val port = if (uri.port == -1) (if (secure) 443 else 80) else uri.port
            val raw = Socket()
            try {
                raw.connect(InetSocketAddress(host.removePrefix("[").removeSuffix("]"), port), TIMEOUT)
                raw.soTimeout = TIMEOUT
                val socket = if (secure) {
                    val tls = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, host, port, true) as SSLSocket
                    tls.startHandshake()
                    // SSLSocket checks the chain but not the name.
                    if (!HttpsURLConnection.getDefaultHostnameVerifier().verify(host, tls.session)) throw IOException("hostname")
                    tls
                } else raw
                val key = Base64.getEncoder().encodeToString(ByteArray(16).also(random::nextBytes))
                val target = (uri.rawPath?.ifEmpty { null } ?: "/") + (uri.rawQuery?.let { "?$it" } ?: "")
                val authority = if (uri.port == -1) host else "$host:$port"
                val request = "GET $target HTTP/1.1\r\nHost: $authority\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
                    "Sec-WebSocket-Key: $key\r\nSec-WebSocket-Version: 13\r\n" +
                    (if (protocols.isEmpty()) "" else "Sec-WebSocket-Protocol: ${protocols.joinToString(", ")}\r\n") + "\r\n"
                val output = socket.getOutputStream()
                output.write(request.toByteArray(Charsets.UTF_8))
                output.flush()
                val input = socket.getInputStream().buffered()
                val response = handshake(input)
                if (!validate(response, key, protocols)) throw ProtocolException("upgrade")
                socket.soTimeout = READ_TIMEOUT
                return WebSocket(socket, input, output)
            } catch (error: Exception) {
                try { raw.close() } catch (_: IOException) { }
                throw error
            }
        }

        /** `Sec-WebSocket-Accept` for a key: SHA-1 of the key and RFC 6455's GUID, in Base64. */
        fun accept(key: String): String = Base64.getEncoder()
            .encodeToString(MessageDigest.getInstance("SHA-1").digest((key + GUID).toByteArray(Charsets.US_ASCII)))

        /** Reads the response head up to its empty line: the status line, then lowercased header names and values. */
        fun handshake(input: InputStream): List<Pair<String, String>> {
            val head = ByteArrayOutputStream()
            var last = 0
            while (last != 0x0D0A0D0A) {
                val byte = input.read()
                if (byte < 0) throw EOFException()
                if (head.size() >= 16 * 1024) throw ProtocolException("head")
                head.write(byte)
                last = (last shl 8) or byte
            }
            val lines = head.toString("ISO-8859-1").split("\r\n").filter { it.isNotEmpty() }
            return listOf("" to lines.first()) + lines.drop(1).map { line ->
                line.substringBefore(':').trim().lowercase() to line.substringAfter(':', "").trim()
            }
        }

        /** Whether a response head accepts the upgrade for `key`, with one of `protocols` or none. */
        fun validate(response: List<Pair<String, String>>, key: String, protocols: List<String>): Boolean {
            val status = response.firstOrNull()?.second?.split(' ')
            fun header(name: String) = response.drop(1).filter { it.first == name }.map { it.second }
            val protocol = header("sec-websocket-protocol")
            return status != null && status.size >= 2 && status[0].startsWith("HTTP/1.1") && status[1] == "101" &&
                header("upgrade").any { it.equals("websocket", ignoreCase = true) } &&
                header("connection").any { value -> value.split(',').any { it.trim().equals("upgrade", ignoreCase = true) } } &&
                header("sec-websocket-accept") == listOf(accept(key)) &&
                (protocol.isEmpty() || (protocol.size == 1 && protocol[0] in protocols))
        }

        /** A final client frame: masked, as RFC 6455 requires of clients. */
        fun encode(opcode: Int, payload: ByteArray, mask: ByteArray): ByteArray {
            val frame = ByteArrayOutputStream(payload.size + 14)
            frame.write(0x80 or opcode)
            when {
                payload.size < 126 -> frame.write(0x80 or payload.size)
                payload.size < 65536 -> {
                    frame.write(0x80 or 126)
                    frame.write(payload.size shr 8); frame.write(payload.size and 0xFF)
                }
                else -> {
                    frame.write(0x80 or 127)
                    for (shift in 56 downTo 0 step 8) frame.write((payload.size.toLong() shr shift).toInt() and 0xFF)
                }
            }
            frame.write(mask)
            payload.forEachIndexed { i, byte -> frame.write(byte.toInt() xor mask[i % 4].toInt()) }
            return frame.toByteArray()
        }

        /** Reads one server frame, which must be unmasked and at most `limit` bytes. */
        fun decode(input: DataInputStream, limit: Int): Frame {
            val first = input.readUnsignedByte()
            val second = input.readUnsignedByte()
            if (first and 0x70 != 0 || second and 0x80 != 0) throw ProtocolException("frame")
            val opcode = first and 0x0F
            val fin = first and 0x80 != 0
            val length = when (val short = second and 0x7F) {
                126 -> input.readUnsignedShort().toLong()
                127 -> input.readLong()
                else -> short.toLong()
            }
            if (opcode >= OPCODE_CLOSE && (!fin || length > 125)) throw ProtocolException("control")
            if (length < 0 || length > limit) throw ProtocolException("too large")
            return Frame(fin, opcode, ByteArray(length.toInt()).also { input.readFully(it) })
        }
    }
}
