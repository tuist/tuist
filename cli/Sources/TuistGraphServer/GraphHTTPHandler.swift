import Foundation
import NIO
import NIOHTTP1

/// Handles HTTP requests for the graph visualization server.
///
/// Routes:
/// - `GET /`           → generated HTML page that loads `<xcode-graph>` from CDN
/// - `GET /graph.json` → the raw graph JSON
/// - `GET /ws`         → WebSocket upgrade (handled by NIOWebSocket upgrader, not here)
final class GraphHTTPHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: GraphServer
    private let htmlPage: Data

    init(server: GraphServer, port: Int) {
        self.server = server
        htmlPage = Data(Self.generateHTML(port: port).utf8)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = unwrapInboundIn(data)
        guard case let .head(request) = reqPart else { return }

        let path = request.uri.split(separator: "?").first.map(String.init) ?? request.uri

        switch path {
        case "/":
            respond(context: context, request: request, data: htmlPage, contentType: "text/html")
        case "/graph.json":
            respond(context: context, request: request, data: server.graphJSON, contentType: "application/json")
        default:
            respondError(context: context, request: request, status: .notFound)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    // MARK: - HTML Generation

    /// The CDN URL for the web component bundle.
    private static let cdnURL = "https://cdn.jsdelivr.net/npm/xcode-graph@1.34.5-4/dist/xcodegraph.js"

    private static func generateHTML(port: Int) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Tuist Graph</title>
          <style>
            html, body { margin: 0; padding: 0; height: 100%; background: #0a0a0c; overflow: hidden; }
            #root { height: 100%; }
            .loading {
              display: flex; align-items: center; justify-content: center;
              height: 100%; color: #e1e4e8; font-family: system-ui, sans-serif;
              font-size: 14px; opacity: 0.5;
            }
          </style>
        </head>
        <body>
          <div id="root"><div class="loading">Loading graph…</div></div>
          <script type="module">
            import '\(cdnURL)';

            let app;

            async function loadGraph() {
              const res = await fetch('/graph.json');
              const raw = await res.json();

              if (!app) {
                app = document.createElement('xcode-graph');
                const root = document.getElementById('root');
                root.textContent = '';
                root.appendChild(app);
              }
              app.loadRawGraph(raw);
            }

            await loadGraph();

            // WebSocket live-reload
            function connectWS() {
              const ws = new WebSocket(`ws://${location.hostname}:\(port)/ws`);
              ws.onmessage = (event) => {
                if (event.data === 'reload') {
                  loadGraph();
                }
              };
              ws.onclose = () => setTimeout(connectWS, 2000);
              ws.onerror = () => ws.close();
            }
            connectWS();
          </script>
        </body>
        </html>
        """
    }

    // MARK: - Response Helpers

    private func respond(
        context: ChannelHandlerContext,
        request: HTTPRequestHead,
        data: Data,
        contentType: String
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: contentType)
        headers.add(name: "content-length", value: "\(data.count)")

        let head = HTTPResponseHead(version: request.version, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: data)))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func respondError(
        context: ChannelHandlerContext,
        request: HTTPRequestHead,
        status: HTTPResponseStatus
    ) {
        let body = "\(status.code) \(status.reasonPhrase)"
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "text/plain")
        headers.add(name: "content-length", value: "\(body.utf8.count)")

        let head = HTTPResponseHead(version: request.version, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(string: body)))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
