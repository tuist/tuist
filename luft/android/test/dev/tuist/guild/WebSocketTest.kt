package dev.tuist.guild

import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.net.ProtocolException

class WebSocketTest {
    private fun frame(vararg bytes: Int) = DataInputStream(ByteArrayInputStream(ByteArray(bytes.size) { bytes[it].toByte() }))

    private fun fails(block: () -> Unit) = try { block(); false } catch (_: ProtocolException) { true }

    fun testAcceptKey() {
        // RFC 6455, section 1.3.
        check(WebSocket.accept("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    fun testEncodesMaskedTextFrame() {
        // RFC 6455, section 5.7: a masked "Hello".
        val mask = byteArrayOf(0x37, 0xfa.toByte(), 0x21, 0x3d)
        val expected = intArrayOf(0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58).map { it.toByte() }
        check(WebSocket.encode(WebSocket.OPCODE_TEXT, "Hello".toByteArray(), mask).toList() == expected)
    }

    fun testEncodesExtendedLengths() {
        val mask = byteArrayOf(1, 2, 3, 4)
        val medium = WebSocket.encode(WebSocket.OPCODE_TEXT, ByteArray(300), mask)
        check(medium[1] == 0xFE.toByte() && medium[2] == 0x01.toByte() && medium[3] == 0x2C.toByte() && medium.size == 4 + 4 + 300)
        val large = WebSocket.encode(WebSocket.OPCODE_BINARY, ByteArray(70000), mask)
        check(large[1] == 0xFF.toByte() && large.copyOfRange(2, 10).toList() == listOf<Byte>(0, 0, 0, 0, 0, 1, 0x11, 0x70))
        check(large.size == 10 + 4 + 70000 && large[14] == 1.toByte() && large[15] == 2.toByte())
    }

    fun testDecodesServerFrames() {
        val text = WebSocket.decode(frame(0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f), 1024)
        check(text.fin && text.opcode == WebSocket.OPCODE_TEXT && String(text.payload) == "Hello")
        // A fragmented message: a text frame without FIN, then its continuation.
        val first = WebSocket.decode(frame(0x01, 0x03, 0x48, 0x65, 0x6c), 1024)
        val last = WebSocket.decode(frame(0x80, 0x02, 0x6c, 0x6f), 1024)
        check(!first.fin && first.opcode == WebSocket.OPCODE_TEXT && last.fin && last.opcode == WebSocket.OPCODE_CONTINUATION)
        val ping = WebSocket.decode(frame(0x89, 0x00), 1024)
        check(ping.opcode == WebSocket.OPCODE_PING && ping.payload.isEmpty())
        val medium = WebSocket.decode(DataInputStream(ByteArrayInputStream(byteArrayOf(0x82.toByte(), 126, 0x01, 0x2C) + ByteArray(300))), 1024)
        check(medium.payload.size == 300)
    }

    fun testRejectsInvalidFrames() {
        check(fails { WebSocket.decode(frame(0x81, 0x85, 0, 0, 0, 0, 0, 0, 0, 0, 0), 1024) }) // masked by the server
        check(fails { WebSocket.decode(frame(0xC1, 0x00), 1024) }) // reserved bit
        check(fails { WebSocket.decode(frame(0x09, 0x00), 1024) }) // fragmented control frame
        check(fails { WebSocket.decode(frame(0x82, 0x7F, 0, 0, 0, 0, 0, 0x10, 0, 0), 1024) }) // over the limit
        check(fails { WebSocket.decode(frame(0x82, 0x7F, 0x80, 0, 0, 0, 0, 0, 0, 0), 1024) }) // negative length
    }

    fun testValidatesUpgrade() {
        val key = "dGhlIHNhbXBsZSBub25jZQ=="
        val head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\nSec-WebSocket-Protocol: phoenix\r\n\r\n"
        val response = WebSocket.handshake(ByteArrayInputStream(head.toByteArray()))
        check(WebSocket.validate(response, key, listOf("phoenix", "base64url.bearer.phx.token")))
        check(!WebSocket.validate(response, "AAAAAAAAAAAAAAAAAAAAAA==", listOf("phoenix")))
        check(!WebSocket.validate(response, key, listOf("other")))
        val refused = WebSocket.handshake(ByteArrayInputStream("HTTP/1.1 403 Forbidden\r\n\r\n".toByteArray()))
        check(!WebSocket.validate(refused, key, listOf("phoenix")))
    }
}
