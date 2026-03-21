import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket

/// Serves the interactive graph visualization over HTTP with WebSocket live-reload.
///
/// Generates an HTML page that loads the `<xcode-graph>` web component from a CDN
/// and fetches graph data from `/graph.json`. No bundled static assets required.
///
/// Usage:
/// ```swift
/// let server = GraphServer(graphJSON: jsonData)
/// try server.start() // opens browser, blocks until shutdown
/// ```
public final class GraphServer: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _graphJSON: Data
    private nonisolated(unsafe) var channel: Channel?
    private nonisolated(unsafe) var eventLoopGroup: MultiThreadedEventLoopGroup?
    private let port: Int
    private let shouldOpenBrowser: Bool

    /// Connected WebSocket channels for live-reload broadcast.
    private nonisolated(unsafe) var wsClients: [ObjectIdentifier: Channel] = [:]

    /// Thread-safe access to current graph JSON.
    var graphJSON: Data {
        lock.lock()
        defer { lock.unlock() }
        return _graphJSON
    }

    /// Creates a server that serves the given pre-encoded JSON data.
    ///
    /// - Parameters:
    ///   - graphJSON: Pre-encoded JSON data of the graph.
    ///   - port: Port to bind to (default: 8081).
    ///   - openBrowser: Whether to automatically open the browser (default: true).
    public init(graphJSON: Data, port: Int = 8081, openBrowser: Bool = true) {
        _graphJSON = graphJSON
        self.port = port
        shouldOpenBrowser = openBrowser
    }

    /// Replaces the graph data and notifies all connected WebSocket clients to reload.
    public func updateGraph(_ data: Data) {
        lock.lock()
        _graphJSON = data
        let clients = Array(wsClients.values)
        lock.unlock()

        for client in clients {
            WebSocketHandler.send("reload", on: client)
        }
    }

    /// Starts the HTTP server and opens the default browser.
    ///
    /// This method blocks until the server is shut down.
    public func start() throws {
        let server = self
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group

        let websocketUpgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, head in
                let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
                if path == "/ws" {
                    return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
                }
                return channel.eventLoop.makeSucceededFuture(nil)
            },
            upgradePipelineHandler: { channel, _ in
                channel.pipeline.addHandler(
                    WebSocketHandler(
                        onConnect: { server.addWebSocketClient($0) },
                        onDisconnect: { server.removeWebSocketClient($0) }
                    )
                )
            }
        )

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let httpHandler = GraphHTTPHandler(server: server, port: server.port)
                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (
                        upgraders: [websocketUpgrader] as [HTTPServerProtocolUpgrader],
                        completionHandler: { context in
                            context.pipeline.removeHandler(httpHandler, promise: nil)
                        }
                    )
                ).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 1)

        do {
            channel = try bootstrap.bind(host: "localhost", port: port).wait()
            if shouldOpenBrowser {
                openBrowser(url: "http://localhost:\(port)")
            }
            try channel?.closeFuture.wait()
        } catch {
            try shutdown()
            throw error
        }
    }

    /// Gracefully shuts down the server.
    public func shutdown() throws {
        try channel?.close().wait()
        try eventLoopGroup?.syncShutdownGracefully()
    }

    // MARK: - WebSocket client management

    private func addWebSocketClient(_ channel: Channel) {
        lock.lock()
        wsClients[ObjectIdentifier(channel)] = channel
        lock.unlock()
    }

    private func removeWebSocketClient(_ channel: Channel) {
        lock.lock()
        wsClients.removeValue(forKey: ObjectIdentifier(channel))
        lock.unlock()
    }

    private func openBrowser(url: String) {
        #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [url]
            try? process.run()
        #elseif os(Linux)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
            process.arguments = [url]
            try? process.run()
        #endif
    }
}
