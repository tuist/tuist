import Foundation
import NIO
import NIOEmbedded
import NIOWebSocket
import Testing

@testable import TuistGraphServer

struct WebSocketHandlerTests {
    private func makeChannel(
        onConnect: @escaping (Channel) -> Void = { _ in },
        onDisconnect: @escaping (Channel) -> Void = { _ in }
    ) throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(
            WebSocketHandler(onConnect: onConnect, onDisconnect: onDisconnect)
        ).wait()
        return channel
    }

    @Test func ping_receives_pong_response() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let pingData = channel.allocator.buffer(string: "ping-data")
        let pingFrame = WebSocketFrame(fin: true, opcode: .ping, data: pingData)
        try channel.writeInbound(pingFrame)

        let response: WebSocketFrame = try #require(try channel.readOutbound())
        #expect(response.opcode == .pong)
    }

    @Test func connection_close_closes_channel() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: channel.allocator.buffer(capacity: 0))
        try channel.writeInbound(closeFrame)

        #expect(!channel.isActive)
    }

    @Test func send_writes_text_frame_to_channel() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        WebSocketHandler.send("reload", on: channel)

        let frame: WebSocketFrame = try #require(try channel.readOutbound())
        #expect(frame.opcode == .text)

        var data = frame.data
        let text = data.readString(length: data.readableBytes)
        #expect(text == "reload")
    }
}
