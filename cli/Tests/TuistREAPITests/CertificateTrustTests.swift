import FileSystem
import FileSystemTesting
import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import NIOTLS
import Testing
import TuistEnvironment
import TuistEnvironmentTesting
import TuistTestSupport

@testable import TuistHTTP
@testable import TuistREAPI

struct CertificateTrustTests {
    @Test
    func rejects_all_twelve_policy_keys_and_preserves_native_verification_failure() throws {
        let blocked = try certificates("issuer-roots") + certificates("distrusted-intermediates")
        #expect(blocked.count == 12)
        for certificate in blocked {
            #expect(!isVerified(REAPITransport.verifyCertificate(.certificateVerified, certificate: certificate)))
        }
        let positive = try certificates("positive-isrg-root-x1") + certificates("positive-isrg-r11")
        #expect(positive.count == 2)
        for certificate in positive {
            #expect(isVerified(REAPITransport.verifyCertificate(.certificateVerified, certificate: certificate)))
            #expect(!isVerified(REAPITransport.verifyCertificate(.failed, certificate: certificate)))
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func actual_TLS_preserves_private_CA_hostname_and_unknown_CA_checks() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory).pathString
        try openssl([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
            "-subj", "/CN=Tuist test-only private CA", "-keyout", "root.key", "-out", "root.pem",
        ], in: directory)
        try openssl([
            "req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256", "-subj", "/CN=localhost",
            "-keyout", "leaf.key", "-out", "leaf.csr",
        ], in: directory)
        try Data("""
        basicConstraints=critical,CA:false
        keyUsage=critical,digitalSignature,keyEncipherment
        extendedKeyUsage=serverAuth
        subjectAltName=DNS:localhost
        """.utf8).write(to: URL(fileURLWithPath: directory).appendingPathComponent("leaf.ext"))
        try openssl([
            "x509", "-req", "-in", "leaf.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial",
            "-out", "leaf.pem", "-days", "1", "-sha256", "-extfile", "leaf.ext",
        ], in: directory)
        let root = try #require(NIOSSLCertificate.fromPEMFile("\(directory)/root.pem").first)
        let leaf = try #require(NIOSSLCertificate.fromPEMFile("\(directory)/leaf.pem").first)
        let key = try NIOSSLPrivateKey(file: "\(directory)/leaf.key", format: .pem)
        let serverContext = try NIOSSLContext(configuration: .makeServerConfiguration(
            certificateChain: [.certificate(leaf), .certificate(root)], privateKey: .privateKey(key)
        ))
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        var server: Channel?
        do {
            let bound = try await ServerBootstrap(group: group)
                .childChannelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandlers(
                            NIOSSLServerHandler(context: serverContext),
                            TestHTTPSResponder()
                        )
                    }
                }.bind(host: "127.0.0.1", port: 0).get()
            server = bound
            let port = try #require(bound.localAddress?.port)
            var trusted = TLSConfiguration.makeClientConfiguration()
            trusted.additionalTrustRoots = [.certificates([root])]
            var explicit = TLSConfiguration.makeClientConfiguration()
            explicit.trustRoots = .certificates([root])
            var fileAnchors = TLSConfiguration.makeClientConfiguration()
            fileAnchors.additionalTrustRoots = [.file("\(directory)/root.pem")]
            let deniedRoot = Set([try CertificateTrust.spkiHash(Data(root.toDERBytes()))])
            let deniedLeaf = Set([try CertificateTrust.spkiHash(Data(leaf.toDERBytes()))])
            for configuration in [trusted, explicit, fileAnchors] {
                let context = try NIOSSLContext(configuration: configuration)
                try await Self.handshake(group: group, host: "127.0.0.1", port: port, hostname: "localhost", context: context)
                for denied in [deniedRoot, deniedLeaf] {
                    do {
                        try await Self.handshake(
                            group: group,
                            host: "127.0.0.1",
                            port: port,
                            hostname: "localhost",
                            context: context,
                            additionalBlockedSPKIHashes: denied
                        )
                        Issue.record("Accepted a generated key after adding it to the deny policy")
                    } catch {
                        #expect(error is NIOSSLError && String(describing: error).contains("CERTIFICATE_VERIFY_FAILED"))
                    }
                }
                await #expect(throws: (any Error).self) {
                    try await Self.handshake(
                        group: group,
                        host: "127.0.0.1",
                        port: port,
                        hostname: "wrong.example.test",
                        context: context
                    )
                }
            }
            var untrusted = TLSConfiguration.makeClientConfiguration()
            untrusted.additionalTrustRoots = [.certificates(try certificates("positive-isrg-root-x1"))]
            let untrustedContext = try NIOSSLContext(configuration: untrusted)
            await #expect(throws: (any Error).self) {
                try await Self.handshake(
                    group: group,
                    host: "127.0.0.1",
                    port: port,
                    hostname: "localhost",
                    context: untrustedContext
                )
            }
            #if canImport(Security)
                let environment = try #require(Environment.mocked)
                environment.variables["TUIST_CA_CERTIFICATE"] = "\(directory)/root.pem"
                let session = URLSession.tuist(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                let url = try #require(URL(string: "https://localhost:\(port)/"))
                let (data, response) = try await session.data(from: url)
                #expect((response as? HTTPURLResponse)?.statusCode == 200)
                #expect(String(decoding: data, as: UTF8.self) == "ok")
                for denied in [deniedRoot, deniedLeaf] {
                    let deniedSession = URLSession.tuist(configuration: .ephemeral, additionalBlockedSPKIHashes: denied)
                    defer { deniedSession.invalidateAndCancel() }
                    do {
                        _ = try await deniedSession.data(from: url)
                        Issue.record("Accepted a generated key after adding it to the deny policy")
                    } catch {
                        #expect((error as NSError).domain == NSURLErrorDomain)
                        #expect((error as NSError).code == NSURLErrorCancelled)
                    }
                }
                let wrongHostname = try #require(URL(string: "https://127.0.0.1:\(port)/"))
                await #expect(throws: (any Error).self) { try await session.data(from: wrongHostname) }
                environment.variables.removeValue(forKey: "TUIST_CA_CERTIFICATE")
                let untrustedSession = URLSession.tuist(configuration: .ephemeral)
                defer { untrustedSession.invalidateAndCancel() }
                await #expect(throws: (any Error).self) { try await untrustedSession.data(from: url) }
            #endif
            try await bound.close().get()
            try await group.shutdownGracefully()
        } catch {
            if let server { try? await server.close().get() }
            try? await group.shutdownGracefully()
            throw error
        }
    }

    @Test
    func refuses_disabled_or_incomplete_verification() throws {
        for level in [CertificateVerification.none, .noHostnameVerification] {
            var configuration = TLSConfiguration.makeClientConfiguration()
            configuration.certificateVerification = level
            let context = try NIOSSLContext(configuration: configuration)
            #expect(throws: NIOSSLError.self) {
                try REAPITransport.makeTLSHandler(context: context, serverHostname: "localhost")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TUIST_TRUST_LIVE"] == "1"))
    func actual_TLS_rejects_all_public_controls_and_accepts_unrelated_HTTPS() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let context = try NIOSSLContext(configuration: .makeClientConfiguration())
            for issuer in ["emudhra", "aaa-emudhra"] {
                for prefix in ["dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"] {
                    let host = "\(prefix)-\(issuer).we-have-a-problem.com"
                    do {
                        try await Self.handshake(group: group, host: host, port: 443, hostname: host, context: context)
                        Issue.record("Accepted a public negative TLS control: \(host)")
                    } catch {
                        #expect(
                            error is NIOSSLError && String(describing: error).contains("CERTIFICATE_VERIFY_FAILED"),
                            "Expected certificate rejection, not a network/protocol/timeout failure: \(error)"
                        )
                    }
                }
            }
            try await Self.handshake(
                group: group,
                host: "letsencrypt.org",
                port: 443,
                hostname: "letsencrypt.org",
                context: context
            )
            try await group.shutdownGracefully()
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    private func certificates(_ name: String) throws -> [NIOSSLCertificate] {
        let path = TestPaths.fixturesDirectory.appending(components: "CertificateTrust", "\(name).pem")
        return try NIOSSLCertificate.fromPEMFile(path.pathString)
    }

    private func isVerified(_ result: NIOSSLVerificationResult) -> Bool {
        if case .certificateVerified = result { return true }
        return false
    }

    private func openssl(_ arguments: [String], in directory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "Could not generate ephemeral TLS test certificates")
    }

    private static func handshake(
        group: EventLoopGroup, host: String, port: Int, hostname: String, context: NIOSSLContext,
        additionalBlockedSPKIHashes: Set<String> = []
    ) async throws {
        let promise = group.next().makePromise(of: Void.self)
        let observer = TLSHandshakeObserver(promise: promise)
        let channel = try await ClientBootstrap(group: group).connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandlers(
                        REAPITransport.makeTLSHandler(
                            context: context,
                            serverHostname: hostname,
                            additionalBlockedSPKIHashes: additionalBlockedSPKIHashes
                        ), observer
                    )
                }
            }.connect(host: host, port: port).get()
        let timeout = channel.eventLoop.scheduleTask(in: .seconds(10)) {
            observer.finish(.failure(TLSHandshakeObserver.Failure.timeout))
            channel.close(promise: nil)
        }
        defer { timeout.cancel() }
        do {
            try await promise.futureResult.get()
            try? await channel.close().get()
        } catch {
            try? await channel.close().get()
            throw error
        }
    }
}

/// Mutable state belongs exclusively to the channel's event loop. The test uses
/// one event loop for the promise, timeout and channel callbacks.
private final class TLSHandshakeObserver: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    enum Failure: Error { case timeout, closedBeforeHandshake }
    private let promise: EventLoopPromise<Void>
    private var completed = false

    init(promise: EventLoopPromise<Void>) { self.promise = promise }

    func finish(_ result: Result<Void, Error>) {
        guard !completed else { return }
        completed = true
        promise.completeWith(result)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case TLSUserEvent.handshakeCompleted = event { finish(.success(())) }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finish(.failure(error))
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish(.failure(Failure.closedBeforeHandshake))
        context.fireChannelInactive()
    }
}

private final class TestHTTPSResponder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data _: NIOAny) {
        let response = context.channel.allocator
            .buffer(string: "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        context.writeAndFlush(NIOAny(response), promise: nil)
    }
}
