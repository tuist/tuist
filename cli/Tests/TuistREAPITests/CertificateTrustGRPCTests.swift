import FileSystem
import FileSystemTesting
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOCore
import NIOPosix
import NIOSSL
import Path
import Synchronization
import Testing
import TuistEnvironment
import TuistEnvironmentTesting
@testable import TuistHTTP
@testable import TuistREAPI

struct CertificateTrustGRPCTests {
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func production_transport_protects_actual_h2_RPC_and_absent_anchor_before_metadata_delivery() async throws {
        try #require(HTTPSettings.current.useEnvironmentProxy)
        try #require(HTTPSettings.current.caCertificatePath == nil)
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let fixture = try await makeFixture(in: directory.pathString)
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CA_CERTIFICATE"] = fixture.rootPath
        let state = TrustRPCState()
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .tls(
                certificateChain: [.file(path: fixture.chainPath, format: .pem)],
                privateKey: .file(path: fixture.keyPath, format: .pem)
            ) { $0.requireALPN = true }
        )
        let server = GRPCServer(transport: transport, services: [TrustCapabilities(state: state)])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let address = try await transport.listeningAddress
            let endpoint = GRPCEndpoint(host: "localhost", explicitPort: try #require(address.ipv4?.port), isTLS: true)
            try await rpc(endpoint: endpoint)
            #expect(await state.attempts == 1)
            for hash in fixture.hashes {
                do {
                    try await rpc(endpoint: endpoint, additionalBlockedSPKIHashes: [hash])
                    Issue.record("An otherwise accepted key reached the RPC after being denied")
                } catch let error as RPCError {
                    #expect(error.code == .unavailable)
                }
                #expect(await state.attempts == 1)
            }
            environment.variables.removeValue(forKey: "TUIST_CA_CERTIFICATE")
            do {
                try await rpc(endpoint: endpoint)
                Issue.record("An unknown private CA reached the RPC")
            } catch let error as RPCError {
                #expect(error.code == .unavailable)
            }
            #expect(await state.attempts == 1)
            environment.variables["TUIST_CA_CERTIFICATE"] = fixture.rootPath
            try await rpc(endpoint: endpoint)
            #expect(await state.attempts == 2)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func actual_HTTPS_CONNECT_protects_both_PKIs_and_separates_proxy_and_origin_credentials() async throws {
        try #require(HTTPSettings.current.useEnvironmentProxy)
        try #require(HTTPSettings.current.caCertificatePath == nil)
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let fixture = try await makeFixture(in: directory.pathString)
        let proxyDirectory = directory.appending(component: "proxy")
        try await fileSystem.makeDirectory(at: proxyDirectory)
        let proxyFixture = try await makeFixture(in: proxyDirectory.pathString)
        let anchors = try await fileSystem.readTextFile(at: AbsolutePath(validating: fixture.rootPath))
            + fileSystem.readTextFile(at: AbsolutePath(validating: proxyFixture.rootPath))
        let rootsPath = directory.appending(component: "combined-roots.pem")
        try await fileSystem.writeText(anchors, at: rootsPath)
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CA_CERTIFICATE"] = rootsPath.pathString
        let state = TrustRPCState()
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .tls(
                certificateChain: [.file(path: fixture.chainPath, format: .pem)],
                privateKey: .file(path: fixture.keyPath, format: .pem)
            ) { $0.requireALPN = true }
        )
        let server = GRPCServer(transport: transport, services: [TrustCapabilities(state: state)])
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let address = try await transport.listeningAddress
            let port = try #require(address.ipv4?.port)
            let endpoint = GRPCEndpoint(host: "localhost", explicitPort: port, isTLS: true)
            var tls = TLSConfiguration.makeServerConfiguration(
                certificateChain: try NIOSSLCertificate.fromPEMFile(proxyFixture.chainPath).map { .certificate($0) },
                privateKey: .privateKey(try NIOSSLPrivateKey(file: proxyFixture.keyPath, format: .pem))
            )
            tls.applicationProtocols = ["http/1.1"]
            let context = try NIOSSLContext(configuration: tls)
            let proxyState = TrustProxyState()
            let loops = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            var listener: Channel?
            do {
                let proxy = try await ServerBootstrap(group: loops).childChannelInitializer { channel in
                    proxyState.add(channel)
                    return channel.pipeline.addHandlers(
                        NIOSSLServerHandler(context: context),
                        TrustConnectTunnel(port: port, state: proxyState)
                    )
                }.bind(host: "127.0.0.1", port: 0).get()
                listener = proxy
                let proxyPort = try #require(proxy.localAddress?.port)
                environment.variables["HTTPS_PROXY"] = "https://proxy-user:proxy-password@localhost:\(proxyPort)"
                try await rpc(endpoint: endpoint)
                #expect(await state.attempts == 1)
                let authorized = proxyState.headers
                #expect(!authorized.isEmpty)
                for header in authorized {
                    #expect(header
                        .contains("Proxy-Authorization: Basic " + Data("proxy-user:proxy-password".utf8).base64EncodedString()))
                    #expect(!header.contains("origin-test-token"))
                }
                for hash in proxyFixture.hashes {
                    let before = proxyState.headers.count
                    do {
                        try await rpc(endpoint: endpoint, additionalBlockedSPKIHashes: [hash])
                        Issue.record("A denied proxy key accepted CONNECT credentials")
                    } catch let error as RPCError { #expect(error.code == .unavailable) }
                    #expect(proxyState.headers.count == before)
                    #expect(await state.attempts == 1)
                }
                for hash in fixture.hashes {
                    let before = proxyState.headers.count
                    do {
                        try await rpc(endpoint: endpoint, additionalBlockedSPKIHashes: [hash])
                        Issue.record("A denied origin key accepted RPC credentials through CONNECT")
                    } catch let error as RPCError { #expect(error.code == .unavailable) }
                    #expect(proxyState.headers.count > before)
                    #expect(await state.attempts == 1)
                }
                try await rpc(endpoint: endpoint)
                #expect(await state.attempts == 2)
                try await proxy.close().get()
                for channel in proxyState.channels {
                    try? await channel.close().get()
                }
                try await loops.shutdownGracefully()
            } catch {
                if let listener { try? await listener.close().get() }
                for channel in proxyState.channels {
                    try? await channel.close().get()
                }
                try? await loops.shutdownGracefully()
                throw error
            }
        }
    }

    private func rpc(endpoint: GRPCEndpoint, additionalBlockedSPKIHashes: Set<String> = []) async throws {
        let transport = try await REAPITransport.make(
            endpoint: endpoint, additionalBlockedSPKIHashes: additionalBlockedSPKIHashes
        )
        let options: CallOptions = {
            var value = CallOptions.defaults
            value.timeout = .seconds(5)
            value.waitForReady = false
            return value
        }()
        try await withGRPCClient(transport: transport) { client in
            let capabilities = Build_Bazel_Remote_Execution_V2_Capabilities.Client(wrapping: client)
            _ = try await capabilities.getCapabilities(
                .with { $0.instanceName = "private-fixture" },
                metadata: ["authorization": "Bearer origin-test-token", "x-tuist-account-handle": "test-account"],
                options: options
            )
        }
    }

    private struct Fixture {
        let rootPath: String
        let chainPath: String
        let keyPath: String
        let hashes: [String]
    }

    private func makeFixture(in directory: String) async throws -> Fixture {
        let fileSystem = FileSystem()
        var executable: String?
        var candidates = ["/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl"]
        #if os(Linux)
            candidates.append("/usr/bin/openssl")
        #endif
        for candidate in candidates {
            if try await fileSystem.exists(AbsolutePath(validating: candidate)) { executable = candidate; break }
        }
        let openssl = try #require(executable)
        func run(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: openssl)
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0)
        }
        try run([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
            "-subj", "/CN=Tuist RPC fixture root", "-keyout", "root.key", "-out", "root.pem",
            "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign",
        ])
        for name in ["issuer", "leaf"] {
            try run([
                "req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256",
                "-subj", "/CN=Tuist RPC fixture \(name)", "-keyout", "\(name).key", "-out", "\(name).csr",
            ])
        }
        try await fileSystem.writeText("""
        basicConstraints=critical,CA:true,pathlen:0
        keyUsage=critical,keyCertSign,cRLSign
        """, at: AbsolutePath(validating: "\(directory)/issuer.ext"))
        try await fileSystem.writeText("""
        basicConstraints=critical,CA:false
        keyUsage=critical,digitalSignature,keyEncipherment
        extendedKeyUsage=serverAuth
        subjectAltName=DNS:localhost
        """, at: AbsolutePath(validating: "\(directory)/leaf.ext"))
        for (name, issuer) in [("issuer", "root"), ("leaf", "issuer")] {
            try run([
                "x509", "-req", "-in", "\(name).csr", "-CA", "\(issuer).pem", "-CAkey", "\(issuer).key",
                "-CAcreateserial", "-out", "\(name).pem", "-days", "1", "-sha256", "-extfile", "\(name).ext",
            ])
        }
        let leaf = try await fileSystem.readTextFile(at: AbsolutePath(validating: "\(directory)/leaf.pem"))
        let issuer = try await fileSystem.readTextFile(at: AbsolutePath(validating: "\(directory)/issuer.pem"))
        try await fileSystem.writeText(leaf + issuer, at: AbsolutePath(validating: "\(directory)/chain.pem"))
        let hashes = try ["root", "issuer", "leaf"].map { name in
            let certificate = try #require(NIOSSLCertificate.fromPEMFile("\(directory)/\(name).pem").first)
            return try CertificateTrust.spkiHash(Data(certificate.toDERBytes()))
        }
        return Fixture(
            rootPath: "\(directory)/root.pem", chainPath: "\(directory)/chain.pem", keyPath: "\(directory)/leaf.key",
            hashes: hashes
        )
    }
}

private final class TrustProxyState: Sendable {
    private struct State {
        var headers: [String] = []
        var channels: [Channel] = []
    }

    private let state = Mutex(State())
    var headers: [String] { state.withLock { $0.headers } }
    var channels: [Channel] { state.withLock { $0.channels } }
    func add(_ channel: Channel) { state.withLock { $0.channels.append(channel) } }
    func record(_ header: String) { state.withLock { $0.headers.append(header) } }
}

private final class TrustConnectTunnel: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let port: Int
    private let state: TrustProxyState
    private var header = ByteBuffer()
    private var target: Channel?
    private var connecting = false

    init(port: Int, state: TrustProxyState) { self.port = port; self.state = state }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bytes = unwrapInboundIn(data)
        if let target { target.writeAndFlush(bytes, promise: nil); return }
        header.writeBuffer(&bytes)
        guard header.readableBytes <= 16384 else { context.close(promise: nil); return }
        guard !connecting, let text = header.getString(at: header.readerIndex, length: header.readableBytes),
              let end = text.range(of: "\r\n\r\n") else { return }
        guard text.hasPrefix("CONNECT localhost:\(port) HTTP/1.1\r\n") else { context.close(promise: nil); return }
        connecting = true
        state.record(String(text[..<end.upperBound]))
        header.moveReaderIndex(forwardBy: text[..<end.upperBound].utf8.count)
        let client = context.channel
        let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
        ClientBootstrap(group: context.eventLoop).channelInitializer { channel in
            channel.pipeline.addHandler(TrustTunnelRelay(peer: client))
        }.connect(host: "127.0.0.1", port: port).whenComplete { result in
            let (handler, context) = bound.value
            switch result {
            case let .success(target):
                handler.state.add(target)
                handler.target = target
                context.writeAndFlush(
                    NIOAny(context.channel.allocator.buffer(string: "HTTP/1.1 200 Connection Established\r\n\r\n")),
                    promise: nil
                )
                if handler.header.readableBytes > 0 { target.writeAndFlush(handler.header, promise: nil) }
            case .failure: context.close(promise: nil)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) { target?.close(promise: nil); context.fireChannelInactive() }
    func errorCaught(context: ChannelHandlerContext, error _: any Error) {
        target?.close(promise: nil); context.close(promise: nil)
    }
}

private final class TrustTunnelRelay: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let peer: Channel
    init(peer: Channel) { self.peer = peer }
    func channelRead(context _: ChannelHandlerContext, data: NIOAny) { peer.writeAndFlush(unwrapInboundIn(data), promise: nil) }
    func channelInactive(context: ChannelHandlerContext) { peer.close(promise: nil); context.fireChannelInactive() }
    func errorCaught(context: ChannelHandlerContext, error _: any Error) { peer.close(promise: nil); context.close(promise: nil) }
}

private actor TrustRPCState {
    var attempts = 0
    func record() { attempts += 1 }
}

private struct TrustCapabilities: Build_Bazel_Remote_Execution_V2_Capabilities.ServiceProtocol {
    let state: TrustRPCState
    func getCapabilities(
        request: ServerRequest<Build_Bazel_Remote_Execution_V2_GetCapabilitiesRequest>, context _: ServerContext
    ) async throws -> ServerResponse<Build_Bazel_Remote_Execution_V2_ServerCapabilities> {
        #expect(request.message.instanceName == "private-fixture")
        #expect(Array(request.metadata[stringValues: "authorization"]) == ["Bearer origin-test-token"])
        #expect(Array(request.metadata[stringValues: "proxy-authorization"]).isEmpty)
        #expect(Array(request.metadata[stringValues: "x-tuist-account-handle"]) == ["test-account"])
        await state.record()
        return ServerResponse(message: .with { $0.cacheCapabilities.digestFunctions = [.sha256] }, metadata: [:])
    }
}
