#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import HTTPTypes
    import NIOCore
    import NIOPosix
    import NIOSSL
    import Security
    import Synchronization
    import Testing
    import TuistEnvironment
    import TuistEnvironmentTesting

    @testable import TuistHTTP

    struct CertificateTrustTransportTests {
        @Test(.inTemporaryDirectory, .withMockedEnvironment())
        func actual_transport_denies_leaf_intermediate_and_absent_root_before_HTTP_delivery() async throws {
            let directory = try #require(FileSystem.temporaryTestDirectory).pathString
            try await makeFixture(in: directory)
            let environment = try #require(Environment.mocked)
            environment.variables["TUIST_CA_CERTIFICATE"] = "\(directory)/root.pem"
            let certificates = try ["root", "issuer", "leaf"].map { name in
                let pem = try Data(contentsOf: URL(fileURLWithPath: "\(directory)/\(name).pem"))
                return try #require(CACertificateLoader.parse(from: pem).first)
            }
            let hashes = try certificates.map { try CertificateTrust.spkiHash(SecCertificateCopyData($0) as Data) }
            let context = try NIOSSLContext(configuration: .makeServerConfiguration(
                certificateChain: try NIOSSLCertificate.fromPEMFile("\(directory)/chain.pem").map { .certificate($0) },
                privateKey: .privateKey(try NIOSSLPrivateKey(file: "\(directory)/leaf.key", format: .pem))
            ))
            let requests = TrustHTTPRequests()
            let loops = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            var listener: Channel?
            do {
                let server = try await ServerBootstrap(group: loops).childChannelInitializer { channel in
                    channel.pipeline.addHandlers(
                        NIOSSLServerHandler(context: context),
                        TrustHTTPResponder(requests: requests)
                    )
                }.bind(host: "127.0.0.1", port: 0).get()
                listener = server
                let port = try #require(server.localAddress?.port)
                try await send(port: port)
                #expect(requests.headers.count == 1)
                for hash in hashes {
                    do {
                        try await send(port: port, denied: [hash])
                        Issue.record("An otherwise accepted key delivered HTTP credentials after being denied")
                    } catch {
                        #expect((error as NSError).domain == NSURLErrorDomain)
                        #expect((error as NSError).code == NSURLErrorCancelled)
                    }
                    #expect(requests.headers.count == 1)
                }
                await #expect(throws: (any Error).self) { try await send(port: port, host: "127.0.0.1") }
                environment.variables.removeValue(forKey: "TUIST_CA_CERTIFICATE")
                await #expect(throws: (any Error).self) { try await send(port: port) }
                #expect(requests.headers.count == 1)
                environment.variables["TUIST_CA_CERTIFICATE"] = "\(directory)/root.pem"
                try await send(port: port)
                let delivered = requests.headers
                #expect(delivered.count == 2)
                #expect(delivered.allSatisfy { $0.lowercased().contains("authorization: bearer local-test-token\r\n") })
                try await server.close().get()
                try await loops.shutdownGracefully()
            } catch {
                if let listener { try? await listener.close().get() }
                try? await loops.shutdownGracefully()
                throw error
            }
        }

        private func send(port: Int, host: String = "localhost", denied: Set<String> = []) async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 10
            let session = URLSession.tuist(configuration: configuration, additionalBlockedSPKIHashes: denied)
            defer { session.invalidateAndCancel() }
            let url = try #require(URL(string: "https://\(host):\(port)/"))
            let (response, _) = try await TuistURLSessionTransport(session: session).send(
                .init(
                    method: .get, scheme: "https", authority: "\(host):\(port)", path: "/",
                    headerFields: [.authorization: "Bearer local-test-token"]
                ),
                body: nil, baseURL: url, operationID: "localCertificateTrust"
            )
            #expect(response.status == .ok)
        }

        private func makeFixture(in directory: String) async throws {
            let fileSystem = FileSystem()
            let candidates = ["/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl"]
            var executable: String?
            for candidate in candidates {
                if try await fileSystem.exists(.init(validating: candidate)) { executable = candidate; break }
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
                "-subj", "/CN=Tuist HTTP fixture root", "-keyout", "root.key", "-out", "root.pem",
                "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign",
            ])
            for name in ["issuer", "leaf"] {
                try run([
                    "req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256",
                    "-subj", "/CN=Tuist HTTP fixture \(name)", "-keyout", "\(name).key", "-out", "\(name).csr",
                ])
            }
            try await fileSystem.writeText("""
            basicConstraints=critical,CA:true,pathlen:0
            keyUsage=critical,keyCertSign,cRLSign
            """, at: .init(validating: "\(directory)/issuer.ext"))
            try await fileSystem.writeText("""
            basicConstraints=critical,CA:false
            keyUsage=critical,digitalSignature,keyEncipherment
            extendedKeyUsage=serverAuth
            subjectAltName=DNS:localhost
            """, at: .init(validating: "\(directory)/leaf.ext"))
            for (name, issuer) in [("issuer", "root"), ("leaf", "issuer")] {
                try run([
                    "x509", "-req", "-in", "\(name).csr", "-CA", "\(issuer).pem", "-CAkey", "\(issuer).key",
                    "-CAcreateserial", "-out", "\(name).pem", "-days", "1", "-sha256", "-extfile", "\(name).ext",
                ])
            }
            let leaf = try await fileSystem.readTextFile(at: .init(validating: "\(directory)/leaf.pem"))
            let issuer = try await fileSystem.readTextFile(at: .init(validating: "\(directory)/issuer.pem"))
            try await fileSystem.writeText(leaf + issuer, at: .init(validating: "\(directory)/chain.pem"))
        }
    }

    private final class TrustHTTPRequests: Sendable {
        private let state = Mutex<[String]>([])
        var headers: [String] { state.withLock { $0 } }
        func record(_ header: String) { state.withLock { $0.append(header) } }
    }

    private final class TrustHTTPResponder: ChannelInboundHandler {
        typealias InboundIn = ByteBuffer
        private let requests: TrustHTTPRequests
        private var buffer = ByteBuffer()

        init(requests: TrustHTTPRequests) { self.requests = requests }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var bytes = unwrapInboundIn(data)
            buffer.writeBuffer(&bytes)
            guard let header = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes),
                  header.contains("\r\n\r\n") else { return }
            requests.record(header)
            let response = context.channel.allocator
                .buffer(string: "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
            context.writeAndFlush(NIOAny(response), promise: nil)
        }

        func errorCaught(context: ChannelHandlerContext, error _: any Error) { context.close(promise: nil) }
    }
#endif
