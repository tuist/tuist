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
    /// Pure, I/O-free part of the transport config. Extracted so tests can inspect the
    /// fields the client sets (authority, flow-control window, keepalive) without having
    /// to stand up TLS or a proxy. `make` fills in the TLS/proxy-dependent callback on top.
    static func baseConfig(authority: String) -> HTTP2ClientTransport.Posix.Config {
        var config = HTTP2ClientTransport.Posix.Config.defaults
        config.http2.authority = authority
        config.http2.targetWindowSize = 32 * 1024 * 1024
        // Keepalive detects a wedged connection whose TCP socket is still open but whose peer
        // has gone silent. Without it, a stuck stream only unblocks when the OS or peer closes
        // the socket, which in traces from self-hosted customers has taken 60-80 seconds.
        //
        // Server-side policy on grpc-go, grpc-java, bazel-remote, Buildbarn and BuildBuddy
        // defaults `keepalive.EnforcementPolicy.MinTime` to 5 minutes with
        // `PermitWithoutStream = false`: a client that pings more often than that collects a
        // strike and eventually gets `GOAWAY ENHANCE_YOUR_CALM`. 60 seconds is below that, but
        // grpc-go resets the strike counter whenever the server sends data or headers, so pings
        // issued while the server is actively replying are safe. A stream where the server
        // itself goes quiet past 3 minutes could still accumulate strikes; our batch deadline
        // (~62 seconds) fires well before that, which is a design feature, not an accident.
        //
        // `allowWithoutCalls: false` means we only ping while a stream is active, so an idle
        // connection does not generate traffic a stricter server could count against us.
        config.connection.keepalive = HTTP2ClientTransport.Config.Keepalive(
            time: .seconds(60),
            timeout: .seconds(20),
            allowWithoutCalls: false
        )
        return config
    }

    static func make(
        endpoint: GRPCEndpoint,
        fileSystem: FileSysteming = FileSystem(),
        additionalBlockedSPKIHashes: Set<String> = []
    ) async throws -> HTTP2ClientTransport.Posix {
        let variables = Environment.current.variables
        let ca = variables["TUIST_CA_CERTIFICATE"].flatMap { $0.isEmpty ? nil : $0 } ?? HTTPSettings.current.caCertificatePath
        let tls = try await clientTLSConfiguration(ca: ca, fileSystem: fileSystem)
        let context = endpoint.isTLS ? try NIOSSLContext(configuration: tls) : nil
        let proxy = try proxyURL(endpoint: endpoint, variables: variables, enabled: HTTPSettings.current.useEnvironmentProxy)
        var proxyTLS = tls
        proxyTLS.applicationProtocols = ["http/1.1"]
        let proxyContext = proxy?.scheme == "https" ? try NIOSSLContext(configuration: proxyTLS) : nil
        var config = baseConfig(authority: endpoint.authority)
        config.channelDebuggingCallbacks.onCreateTCPConnection = { channel in
            channel.eventLoop.makeCompletedFuture {
                if let context {
                    try channel.pipeline.syncOperations.addHandler(
                        makeTLSHandler(
                            context: context, serverHostname: endpoint.host,
                            additionalBlockedSPKIHashes: additionalBlockedSPKIHashes
                        ),
                        position: .first
                    )
                }
                if let proxy {
                    try channel.pipeline.syncOperations.addHandler(
                        REAPIProxyTunnel(request: proxyConnectRequest(authority: endpoint.authority, proxy: proxy)),
                        position: .first
                    )
                }
                if let proxyContext, let host = proxy?.host {
                    try channel.pipeline.syncOperations.addHandler(
                        makeTLSHandler(
                            context: proxyContext, serverHostname: host,
                            additionalBlockedSPKIHashes: additionalBlockedSPKIHashes
                        ),
                        position: .first
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

    private static func clientTLSConfiguration(ca: String?, fileSystem: FileSysteming) async throws -> TLSConfiguration {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.applicationProtocols = ["h2"]
        if let ca {
            let bytes = Array(try await fileSystem.readFile(at: AbsolutePath(validating: URL(fileURLWithPath: ca).path)))
            let pem = (try? NIOSSLCertificate.fromPEMBytes(bytes)) ?? []
            let certificates = try pem.isEmpty ? [NIOSSLCertificate(bytes: bytes, format: .der)] : pem
            tls.additionalTrustRoots = [.certificates(certificates)]
        }
        return tls
    }

    private static func proxyConnectRequest(authority: String, proxy: URL) -> String {
        var headers = "CONNECT \(authority) HTTP/1.1\r\nHost: \(authority)\r\n"
        if let user = proxy.user {
            let credential = Data("\(user):\(proxy.password ?? "")".utf8).base64EncodedString()
            headers += "Proxy-Authorization: Basic \(credential)\r\n"
        }
        return headers + "\r\n"
    }

    static func makeTLSHandler(
        context: NIOSSLContext, serverHostname: String, additionalBlockedSPKIHashes: Set<String> = []
    ) throws -> NIOSSLClientHandler {
        guard case .fullVerification = context.configuration.certificateVerification else {
            throw NIOSSLError.unableToValidateCertificate
        }
        #if canImport(Security)
            if case .default = context.configuration.trustRoots ?? .default {
                let additionalAnchors = try context.configuration.additionalTrustRoots.flatMap { roots -> [Data] in
                    guard case let .certificates(certificates) = roots else { throw NIOSSLError.failedToLoadCertificate }
                    return try certificates.map { Data(try $0.toDERBytes()) }
                }
                // Darwin's default-root path uses Security.framework and skips legacy
                // callbacks. Preserve its normal SSL/hostname policy before the deny.
                return try NIOSSLClientHandler(
                    context: context,
                    serverHostname: serverHostname,
                    customVerificationCallback: { certificates, promise in
                        guard let chain = try? certificates.map({ Data(try $0.toDERBytes()) })
                        else { promise.succeed(.failed); return }
                        CertificateTrust.evaluateTLS(
                            certificateChain: chain,
                            hostname: serverHostname,
                            additionalAnchors: additionalAnchors,
                            additionalBlockedSPKIHashes: additionalBlockedSPKIHashes
                        ) { allowed in
                            promise.succeed(allowed ? .certificateVerified : .failed)
                        }
                    }
                )
            }
        #endif
        // Explicit roots on Darwin and other platforms use BoringSSL verification.
        return try NIOSSLClientHandler(
            context: context,
            serverHostname: serverHostname,
            verificationCallback: { result, certificate in
                verifyCertificate(result, certificate: certificate, additionalBlockedSPKIHashes: additionalBlockedSPKIHashes)
            }
        )
    }

    static func verifyCertificate(
        _ result: NIOSSLVerificationResult,
        certificate: NIOSSLCertificate,
        additionalBlockedSPKIHashes: Set<String> = []
    ) -> NIOSSLVerificationResult {
        guard case .certificateVerified = result,
              let bytes = try? certificate.toDERBytes(),
              CertificateTrust.isAllowed(derCertificate: Data(bytes), additionalBlockedSPKIHashes: additionalBlockedSPKIHashes)
        else { return .failed }
        return .certificateVerified
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
