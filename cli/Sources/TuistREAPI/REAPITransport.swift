import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOCore
import NIOSSL
import Path
import TuistEnvironment
import TuistHTTP

/// Applies the CLI's network settings to both probing and cache traffic.
enum REAPITransport {
    static func make(
        endpoint: GRPCEndpoint,
        fileSystem: FileSysteming = FileSystem()
    ) async throws -> HTTP2ClientTransport.Posix {
        let variables = Environment.current.variables
        let ca = variables["TUIST_CA_CERTIFICATE"].flatMap { $0.isEmpty ? nil : $0 } ?? HTTPSettings.current.caCertificatePath
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.applicationProtocols = ["h2"]
        if let ca {
            let bytes = Array(try await fileSystem.readFile(at: AbsolutePath(validating: URL(fileURLWithPath: ca).path)))
            let certificates = (try? NIOSSLCertificate.fromPEMBytes(bytes)) ?? []
            tls.additionalTrustRoots = [.certificates(try certificates.isEmpty
                    ? [NIOSSLCertificate(bytes: bytes, format: .der)]
                    : certificates)]
        }
        let context = endpoint.isTLS ? try NIOSSLContext(configuration: tls) : nil
        let proxy = try proxyURL(endpoint: endpoint, variables: variables, enabled: HTTPSettings.current.useEnvironmentProxy)
        var proxyTLS = tls
        proxyTLS.applicationProtocols = ["http/1.1"]
        let proxyContext = proxy?.scheme == "https" ? try NIOSSLContext(configuration: proxyTLS) : nil
        var config = HTTP2ClientTransport.Posix.Config.defaults
        config.http2.authority = endpoint.authority
        config.channelDebuggingCallbacks.onCreateTCPConnection = { channel in
            channel.eventLoop.makeCompletedFuture {
                if let context {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLClientHandler(context: context, serverHostname: endpoint.host), position: .first
                    )
                }
                if let proxy {
                    var headers = "CONNECT \(endpoint.authority) HTTP/1.1\r\nHost: \(endpoint.authority)\r\n"
                    if let user = proxy.user {
                        let credential = Data("\(user):\(proxy.password ?? "")".utf8).base64EncodedString()
                        headers += "Proxy-Authorization: Basic \(credential)\r\n"
                    }
                    try channel.pipeline.syncOperations.addHandler(
                        REAPIProxyTunnel(request: headers + "\r\n"), position: .first
                    )
                }
                if let proxyContext, let host = proxy?.host {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLClientHandler(context: proxyContext, serverHostname: host), position: .first
                    )
                }
            }
        }
        return try .http2NIOPosix(
            target: .dns(
                host: proxy?.host ?? endpoint.host,
                port: proxy?.port ?? (proxy == nil ? endpoint.port : proxy?.scheme == "https" ? 443 : 80)
            ),
            transportSecurity: endpoint.isTLS ? .customSecure : .plaintext,
            config: config
        )
    }

    static func proxyURL(endpoint: GRPCEndpoint, variables: [String: String], enabled: Bool) throws -> URL? {
        guard enabled else { return nil }
        let bypass = variables["NO_PROXY"] ?? variables["no_proxy"] ?? ""
        for entry in bypass.split(separator: ",") {
            let host = entry.trimmingCharacters(in: .whitespaces).lowercased()
            if host == "*" || endpoint.host.lowercased() == host || endpoint.authority.lowercased() == host
                || (host.hasPrefix(".") && (endpoint.host.lowercased().hasSuffix(host)
                        || endpoint.host.lowercased() == String(host.dropFirst()))) { return nil }
        }
        let keys = endpoint.isTLS ? ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"] : ["HTTP_PROXY", "http_proxy"]
        guard let value = keys.compactMap({ variables[$0] }).first(where: { !$0.isEmpty }) else { return nil }
        guard let proxy = URL(string: value), ["http", "https"].contains(proxy.scheme ?? ""), proxy.host != nil else {
            throw REAPICacheError.unsupportedProxy
        }
        return proxy
    }
}

/// Buffers TLS/HTTP2 writes until the proxy has established the CONNECT tunnel.
private final class REAPIProxyTunnel: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = NIOAny
    private let request: String
    private var response = ByteBuffer()
    private var pending: [(NIOAny, EventLoopPromise<Void>?)] = []
    private var established = false
    private var timeout: Scheduled<Void>?

    init(request: String) { self.request = request }

    func channelActive(context: ChannelHandlerContext) {
        context.writeAndFlush(NIOAny(context.channel.allocator.buffer(string: request)), promise: nil)
        let bound = NIOLoopBound(context, eventLoop: context.eventLoop)
        timeout = context.eventLoop.scheduleTask(in: .seconds(10)) {
            bound.value.fireErrorCaught(REAPICacheError.proxyConnectionFailed)
            bound.value.close(promise: nil)
        }
        context.fireChannelActive()
    }

    func write(context _: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        pending.append((data, promise))
    }

    func flush(context _: ChannelHandlerContext) {}

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bytes = unwrapInboundIn(data)
        response.writeBuffer(&bytes)
        guard response.readableBytes <= 16 * 1024 else {
            context.fireErrorCaught(REAPICacheError.proxyConnectionFailed)
            context.close(promise: nil)
            return
        }
        guard let text = response.getString(at: response.readerIndex, length: response.readableBytes),
              let end = text.range(of: "\r\n\r\n") else { return }
        guard text.hasPrefix("HTTP/1.1 200 ") || text.hasPrefix("HTTP/1.0 200 ") else {
            context.fireErrorCaught(REAPICacheError.proxyConnectionFailed)
            context.close(promise: nil)
            return
        }
        response.moveReaderIndex(forwardBy: text[..<end.upperBound].utf8.count)
        timeout?.cancel()
        established = true
        context.pipeline.syncOperations.removeHandler(context: context, promise: nil)
        if response.readableBytes > 0 { context.fireChannelRead(wrapInboundOut(response)) }
    }

    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        for (data, promise) in pending {
            context.write(data, promise: promise)
        }
        pending.removeAll()
        context.flush()
        context.leavePipeline(removalToken: removalToken)
    }

    func handlerRemoved(context _: ChannelHandlerContext) {
        timeout?.cancel()
        if !established {
            for (_, promise) in pending {
                promise?.fail(REAPICacheError.proxyConnectionFailed)
            }
            pending.removeAll()
        }
    }
}
