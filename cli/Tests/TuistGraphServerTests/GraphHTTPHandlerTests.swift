import Foundation
import NIO
import NIOEmbedded
import NIOHTTP1
import Testing

@testable import TuistGraphServer

struct GraphHTTPHandlerTests {
    private let graphJSON: Data
    private let server: GraphServer

    init() {
        graphJSON = Data(#"{"nodes":[]}"#.utf8)
        server = GraphServer(graphJSON: graphJSON, port: 8081, openBrowser: false)
    }

    private func makeChannel() throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(GraphHTTPHandler(server: server, port: 8081)).wait()
        return channel
    }

    private func sendRequest(channel: EmbeddedChannel, uri: String) throws -> (HTTPResponseHead, String) {
        let requestHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: uri)
        try channel.writeInbound(HTTPServerRequestPart.head(requestHead))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        var responseHead: HTTPResponseHead?
        var body = ""

        while let part: HTTPServerResponsePart = try channel.readOutbound() {
            switch part {
            case let .head(head):
                responseHead = head
            case let .body(ioData):
                switch ioData {
                case var .byteBuffer(buf):
                    if let str = buf.readString(length: buf.readableBytes) {
                        body += str
                    }
                default:
                    break
                }
            case .end:
                break
            }
        }

        return (try #require(responseHead), body)
    }

    @Test func root_returns_html_with_cdn_url_and_xcode_graph_element() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let (head, body) = try sendRequest(channel: channel, uri: "/")

        #expect(head.status == .ok)
        #expect(head.headers.first(name: "content-type") == "text/html")
        #expect(body.contains("xcode-graph@1.34.5-4"))
        #expect(body.contains("xcode-graph"))
    }

    @Test func graph_json_returns_json_matching_server_data() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let (head, body) = try sendRequest(channel: channel, uri: "/graph.json")

        #expect(head.status == .ok)
        #expect(head.headers.first(name: "content-type") == "application/json")
        #expect(body == #"{"nodes":[]}"#)
    }

    @Test func unknown_path_returns_404() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let (head, _) = try sendRequest(channel: channel, uri: "/unknown")

        #expect(head.status == .notFound)
    }
}
