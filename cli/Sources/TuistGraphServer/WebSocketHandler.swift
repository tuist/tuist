import Foundation
import NIO
import NIOWebSocket

/// Handles individual WebSocket connections and receives broadcast messages from the server.
final class WebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let onConnect: (Channel) -> Void
    private let onDisconnect: (Channel) -> Void

    init(onConnect: @escaping (Channel) -> Void, onDisconnect: @escaping (Channel) -> Void) {
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
    }

    func handlerAdded(context: ChannelHandlerContext) {
        onConnect(context.channel)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        onDisconnect(context.channel)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .connectionClose:
            context.close(promise: nil)
        case .text, .binary, .pong:
            break
        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        context.close(promise: nil)
    }

    /// Send a text message to a WebSocket connection.
    static func send(_ text: String, on channel: Channel) {
        let buffer = channel.allocator.buffer(string: text)
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        channel.writeAndFlush(frame, promise: nil)
    }
}
