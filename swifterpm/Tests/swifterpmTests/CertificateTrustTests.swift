import FileSystem
import FileSystemTesting
import Foundation
import Testing
@testable import SwifterPMCore
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(Security)
    import Darwin
    import Security
#endif

struct CertificateTrustTests {
    @Test
    func hashesAndRejectsAllTwelvePolicyKeys() async throws {
        let blocked = try await certificates("issuer-roots") + certificates("distrusted-intermediates")
        #expect(blocked.count == 12)
        #expect(try Set(blocked.map(CertificateTrust.spkiHash)) == CertificateTrust.blockedSPKIHashes)
        #expect(blocked.allSatisfy { !CertificateTrust.isAllowed(derCertificate: $0) })
        let unrelated = try await certificates("positive-isrg-root-x1") + certificates("positive-isrg-r11")
        #expect(unrelated.count == 2)
        #expect(unrelated.allSatisfy { CertificateTrust.isAllowed(derCertificate: $0) })
    }

    @Test(arguments: [Data(), Data([0x30, 0x80]), Data([0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF]), Data([0x30, 0x81, 0])])
    func malformedDERFailsClosed(_ data: Data) {
        #expect(throws: (any Error).self) { try CertificateTrust.spkiHash(data) }
        #expect(!CertificateTrust.isAllowed(derCertificate: data))
    }

    @Test(arguments: [
        URLError.Code.cancelled,
        .userCancelledAuthentication,
        .secureConnectionFailed,
        .serverCertificateHasBadDate,
        .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot,
        .serverCertificateNotYetValid,
        .clientCertificateRejected,
        .clientCertificateRequired,
        .appTransportSecurityRequiresSecureConnection
    ])
    func securityFailuresAreNeitherRetriedNorConvertedToFallback(_ code: URLError.Code) async throws {
        let attempts = AttemptCounter()
        await #expect(throws: URLError.self) {
            try await HTTPClient.withRetry {
                await attempts.increment()
                throw URLError(code)
            } as Void
        }
        #expect(await attempts.count == 1)
        await #expect(throws: URLError.self) {
            try await HTTPClient.optionalResult { throw URLError(code) } as Void?
        }
        let wrapped = NSError(domain: "test-wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: URLError(code)])
        #expect(throws: URLError.self) { try HTTPClient.requireFallbackAllowed(after: wrapped) }
    }

    @Test
    func ordinaryFallbackRemainsAvailableButCancellationEscapes() async throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://example.test")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        ))
        let status = try #require(HTTPClient.StatusError(response: response, requestedURL: response.url!))
        let absent: Int? = try await HTTPClient.optionalResult { throw status }
        #expect(absent == nil)
        let result = try await HTTPClient.optionalResult { 42 }
        #expect(result == 42)
        await #expect(throws: CancellationError.self) {
            try await HTTPClient.optionalResult { throw CancellationError() } as Void?
        }
    }

    #if canImport(Security)
        @Test
        func factoryPreservesConfigurationAndAlwaysInstallsPolicy() throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 37
            configuration.timeoutIntervalForResource = 123
            let session = CertificateTrust.makeSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let delegate = try #require(session.delegate)
            let productionDelegate = try #require(HTTPClient.session.delegate)
            #expect(type(of: productionDelegate) == type(of: delegate))
            #expect(HTTPClient.session.configuration.timeoutIntervalForRequest == 60)
            #expect(HTTPClient.session.configuration.timeoutIntervalForResource == 600)
            #expect(session.configuration.timeoutIntervalForRequest == 37)
            #expect(session.configuration.timeoutIntervalForResource == 123)
        }

        @Test(.inTemporaryDirectory)
        func acceptedPrivateKeysAreRejectedByActualSessionDataDownloadAndRedirect() async throws {
            let directory = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
            let fixture = try await PrivateTLSFixture.start(in: directory)
            defer { fixture.stop() }
            let root = try #require(SecCertificateCreateWithData(nil, fixture.root as CFData))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 10
            let blockedRoots = try await certificates("issuer-roots").map {
                try #require(SecCertificateCreateWithData(nil, $0 as CFData))
            }
            let baseline = CertificateTrust.makeSession(configuration: configuration, additionalAnchors: blockedRoots + [root])
            defer { baseline.invalidateAndCancel() }
            for attempt in 0 ..< 50 {
                do {
                    let (_, response) = try await baseline.data(from: fixture.url)
                    #expect((response as? HTTPURLResponse)?.statusCode == 200)
                    break
                } catch let error as URLError where error.code == .cannotConnectToHost && attempt < 49 {
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
            let (downloaded, response) = try await baseline.download(from: fixture.url)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            try await fileSystem.remove(downloaded.absolutePath)
            try await checkDeniedTransfers(fixture, root: root, configuration: configuration)
            let wrongHost = try #require(URL(string: fixture.url.absoluteString.replacingOccurrences(
                of: "localhost",
                with: "127.0.0.1"
            )))
            try await expectTrustRejection { _ = try await baseline.data(from: wrongHost) }
            let unknown = CertificateTrust.makeSession(configuration: configuration)
            defer { unknown.invalidateAndCancel() }
            try await expectTrustRejection { _ = try await unknown.data(from: fixture.url) }

            try checkConstructedTrust(fixture, root: root)
            try await checkRegistryPropagation(in: directory, fixture: fixture)
        }

        private func checkDeniedTransfers(
            _ fixture: PrivateTLSFixture, root: SecCertificate, configuration: URLSessionConfiguration
        ) async throws {
            for certificate in [fixture.root, fixture.leaf] {
                let denied = CertificateTrust.makeSession(
                    configuration: configuration, additionalAnchors: [root],
                    additionalBlockedSPKIHashes: [try CertificateTrust.spkiHash(certificate)]
                )
                defer { denied.invalidateAndCancel() }
                try await expectTrustRejection { _ = try await denied.data(from: fixture.url) }
                try await expectTrustRejection { _ = try await denied.download(from: fixture.url) }
                try await withLocalHTTPServer { server in
                    server.respond(to: "/redirect", with: [.redirect(to: fixture.url.absoluteString)])
                    try await expectTrustRejection { _ = try await denied.data(from: server.url(path: "/redirect")) }
                    #expect(server.requestedPaths == ["/redirect"])
                }
            }
        }

        /// Preconfigured native trust proves constructed-anchor checks independently
        /// of additional-anchor filtering.
        private func checkConstructedTrust(_ fixture: PrivateTLSFixture, root: SecCertificate) throws {
            let leaf = try #require(SecCertificateCreateWithData(nil, fixture.leaf as CFData))
            func trust() throws -> SecTrust {
                var trust: SecTrust?
                try #require(SecTrustCreateWithCertificates(leaf, SecPolicyCreateSSL(true, "localhost" as CFString), &trust) ==
                    errSecSuccess)
                let result = try #require(trust)
                try #require(SecTrustSetAnchorCertificates(result, [root] as CFArray) == errSecSuccess)
                return result
            }
            #expect(CertificateTrust.evaluate(try trust(), additionalAnchors: [], additionalBlockedSPKIHashes: []))
            #expect(!CertificateTrust.evaluate(
                try trust(),
                additionalAnchors: [],
                additionalBlockedSPKIHashes: [try CertificateTrust.spkiHash(fixture.root)]
            ))
            let expired = try trust()
            try #require(SecTrustSetVerifyDate(expired, Date().addingTimeInterval(3 * 86400) as CFDate) == errSecSuccess)
            #expect(!CertificateTrust.evaluate(expired, additionalAnchors: [], additionalBlockedSPKIHashes: []))
            var corrupted = fixture.leaf
            corrupted[corrupted.count - 1] ^= 1
            let corruptedLeaf = try #require(SecCertificateCreateWithData(nil, corrupted as CFData))
            var corruptedTrust: SecTrust?
            try #require(SecTrustCreateWithCertificates(
                corruptedLeaf,
                SecPolicyCreateSSL(true, "localhost" as CFString),
                &corruptedTrust
            ) == errSecSuccess)
            #expect(!CertificateTrust.evaluate(
                try #require(corruptedTrust),
                additionalAnchors: [root],
                additionalBlockedSPKIHashes: []
            ))
        }

        /// A checksum-seeding trust failure must escape even after native resolution.
        private func checkRegistryPropagation(in directory: URL, fixture: PrivateTLSFixture) async throws {
            try await Environment.$values.withValue([:]) {
                let netrc = Netrc(configuration: .init(isEnabled: false, forcesNetrc: false, disableKeychain: true), sources: [])
                try await Environment.withNetrc(netrc) {
                    let config = try await RegistryConfig.load(
                        packageDir: directory,
                        configPath: nil,
                        defaultRegistryURL: fixture.url.absoluteString
                    )
                    let cache = try await Cache(root: directory.appendingPathComponent("cache"))
                    let pin = ResolvedPin(
                        identity: "example.package",
                        kind: "registry",
                        location: "",
                        state: .init(branch: nil, revision: nil, version: "1.1.4")
                    )
                    try await expectTrustRejection {
                        _ = try await WorkspaceRestorer.ensureRegistrySource(cache: cache, registryConfig: config, pin: pin)
                    }
                    let scratch = directory.appendingPathComponent("scratch")
                    let download = scratch.appendingPathComponent("registry/downloads/example/package/1.1.4")
                    try await writeMinimalPackageManifest(at: download, name: "Package")
                    try await expectTrustRejection {
                        try await WorkspaceRestorer.cacheNativeRegistryDownloads(
                            scratchDir: scratch, cache: cache, registryConfig: config,
                            resolved: ResolvedPins(originHash: nil, pins: [pin], version: 3)
                        )
                    }
                    #expect(try await fileSystem.exists(download.appendingPathComponent("Package.swift").absolutePath))
                    #expect(try await !WorkspaceRestorer.cachedRegistrySourceExists(
                        cacheRoot: cache.root,
                        registryConfig: config,
                        pin: pin
                    ))
                }
            }
        }

        @Test(.inTemporaryDirectory, .enabled(if: ProcessInfo.processInfo.environment["SWIFTERPM_TRUST_LIVE"] == "1"))
        func productionHTTPClientRejectsPublicControlsForDataAndDownloads() async throws {
            let directory = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
            for issuer in ["emudhra", "aaa-emudhra"] {
                for prefix in ["dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"] {
                    let url = try #require(URL(string: "https://\(prefix)-\(issuer).we-have-a-problem.com/"))
                    try await expectTrustRejection { _ = try await HTTPClient.data(url: url) }
                    try await expectTrustRejection {
                        try await HTTPClient.download(url: url, destination: directory.appendingPathComponent("denied"))
                    }
                    #expect(try await !fileSystem.exists(directory.appendingPathComponent("denied").absolutePath))
                }
            }
            let positive = try #require(URL(string: "https://letsencrypt.org/"))
            #expect(try await !HTTPClient.data(url: positive).isEmpty)
            let downloaded = directory.appendingPathComponent("positive")
            try await HTTPClient.download(url: positive, destination: downloaded)
            #expect(try await fileSystem.exists(downloaded.absolutePath))
        }

        private func expectTrustRejection(_ operation: () async throws -> Void) async throws {
            do {
                try await operation()
                Issue.record("Accepted a certificate-negative control")
            } catch {
                let error = error as NSError
                #expect(error.domain == NSURLErrorDomain)
                #expect(
                    [
                        NSURLErrorCancelled,
                        NSURLErrorServerCertificateUntrusted,
                        NSURLErrorServerCertificateHasUnknownRoot,
                        NSURLErrorServerCertificateHasBadDate,
                    ].contains(error.code),
                    "Expected certificate rejection, not arbitrary network/TLS failure: \(error.code)"
                )
                #expect(throws: (any Error).self) { try HTTPClient.requireFallbackAllowed(after: error) }
            }
        }
    #endif

    private func certificates(_ name: String) async throws -> [Data] {
        let path = try await fixtureURL("CertificateTrust", "\(name).pem")
        let text = try #require(String(bytes: await fileSystem.readFile(at: path.absolutePath), encoding: .utf8))
        return try text.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().map { block in
            let base64 = block.components(separatedBy: "-----END CERTIFICATE-----")[0].filter { !$0.isWhitespace }
            return try #require(Data(base64Encoded: base64))
        }
    }
}

private actor AttemptCounter {
    var count = 0
    func increment() { count += 1 }
}

#if canImport(Security)
    private struct PrivateTLSFixture {
        let root: Data
        let leaf: Data
        let url: URL
        let process: Process

        static func start(in directory: URL) async throws -> Self {
            // LibreSSL's s_server cannot bind a specific interface. Require OpenSSL 3
            // for a loopback-only fixture, rather than exposing a test server on all interfaces.
            var executable: String?
            for candidate in ["/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl"]
                where try await fileSystem.exists(URL(fileURLWithPath: candidate).absolutePath)
            {
                executable = candidate
                break
            }
            let opensslPath = try #require(executable, "Loopback TLS tests require Homebrew OpenSSL 3")
            try await generateRequests(in: directory, opensslPath: opensslPath)
            try await signCertificates(in: directory, opensslPath: opensslPath)
            let port = try availablePort()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: opensslPath)
            process.currentDirectoryURL = directory
            process.arguments = [
                "s_server",
                "-accept",
                "127.0.0.1:\(port)",
                "-cert",
                "leaf.pem",
                "-key",
                "leaf.key",
                "-www",
                "-quiet",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            do {
                return try await Self(
                    root: fileSystem.readFile(at: directory.appendingPathComponent("root.der").absolutePath),
                    leaf: fileSystem.readFile(at: directory.appendingPathComponent("leaf.der").absolutePath),
                    url: #require(URL(string: "https://localhost:\(port)/")), process: process
                )
            } catch {
                process.terminate()
                process.waitUntilExit()
                throw error
            }
        }

        private static func generateRequests(in directory: URL, opensslPath: String) async throws {
            func openssl(_ arguments: [String]) async throws {
                _ = try await SystemProcess.output(opensslPath, arguments, workingDirectory: directory)
            }
            try await openssl([
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-sha256",
                "-days",
                "1",
                "-subj",
                "/CN=SwifterPM test-only private CA",
                "-keyout",
                "root.key",
                "-out",
                "root.pem",
            ])
            try await openssl([
                "req",
                "-new",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-sha256",
                "-subj",
                "/CN=localhost",
                "-keyout",
                "leaf.key",
                "-out",
                "leaf.csr",
            ])
            try await fileSystem.atomicWrite("""
            basicConstraints=critical,CA:false
            keyUsage=critical,digitalSignature,keyEncipherment
            extendedKeyUsage=serverAuth
            subjectAltName=DNS:localhost
            """, to: directory.appendingPathComponent("leaf.ext"))
        }

        private static func signCertificates(in directory: URL, opensslPath: String) async throws {
            func openssl(_ arguments: [String]) async throws {
                _ = try await SystemProcess.output(opensslPath, arguments, workingDirectory: directory)
            }
            try await openssl([
                "x509",
                "-req",
                "-in",
                "leaf.csr",
                "-CA",
                "root.pem",
                "-CAkey",
                "root.key",
                "-CAcreateserial",
                "-out",
                "leaf.pem",
                "-days",
                "1",
                "-sha256",
                "-extfile",
                "leaf.ext",
            ])
            for name in ["root", "leaf"] {
                try await openssl(["x509", "-in", "\(name).pem", "-outform", "DER", "-out", "\(name).der"])
            }
        }

        private static func availablePort() throws -> UInt16 {
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            try #require(socket >= 0)
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let status = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    guard Darwin.bind(socket, $0, length) == 0 else { return Int32(-1) }
                    return getsockname(socket, $0, &length)
                }
            }
            Darwin.close(socket)
            try #require(status == 0)
            return UInt16(bigEndian: address.sin_port)
        }

        func stop() {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
    }
#endif
