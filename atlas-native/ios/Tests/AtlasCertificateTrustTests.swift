import Foundation
import Security
import Testing

struct AtlasCertificateTrustTests {
    @Test func malformedDERFailsClosedAndFactoryPreservesConfiguration() {
        for bytes in [[UInt8](), [0x30], [0x30, 0x80], [0x30, 0x81, 0x01, 0x00]] {
            #expect(!AtlasCertificateTrust.isAllowed(derCertificate: Data(bytes)))
        }
        #expect(AtlasCertificateTrust.blockedSPKIHashes.count == 12)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 10
        let session = AtlasCertificateTrust.makeSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        #expect(session.delegate != nil)
        #expect(session.configuration.timeoutIntervalForRequest == 3)
        #expect(session.configuration.timeoutIntervalForResource == 10)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATLAS_TRUST_LIVE"] == "1"))
    func acceptedNativeLeafAndAnchorAreRejectedByActualSession() async throws {
        let collector = NativeChainCollector()
        let reference = URLSession(configuration: .ephemeral, delegate: collector, delegateQueue: nil)
        defer { reference.invalidateAndCancel() }
        let url = try #require(URL(string: "https://letsencrypt.org/"))
        let (_, response) = try await reference.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let protected = AtlasCertificateTrust.makeSession(configuration: .ephemeral)
        defer { protected.invalidateAndCancel() }
        let (_, protectedResponse) = try await protected.data(from: url)
        #expect((protectedResponse as? HTTPURLResponse)?.statusCode == 200)
        let chain = collector.certificates
        let leaf = try #require(chain.first)
        let root = try #require(chain.last)
        #expect(chain.count > 1)
        for certificate in [leaf, root] {
            let session = AtlasCertificateTrust.makeSession(
                configuration: .ephemeral,
                additionalAnchors: [],
                additionalBlockedSPKIHashes: [try AtlasCertificateTrust.spkiHash(certificate)]
            )
            defer { session.invalidateAndCancel() }
            do {
                _ = try await session.data(from: url)
                Issue.record("Otherwise accepted key was not denied by the application")
            } catch {
                let error = error as NSError
                #expect(error.domain == NSURLErrorDomain)
                #expect([
                    URLError.cancelled.rawValue,
                    URLError.serverCertificateUntrusted.rawValue,
                    URLError.serverCertificateHasUnknownRoot.rawValue
                ].contains(error.code), "Expected certificate/challenge cancellation, got \(error.code)")
            }
        }
    }
}

private final class NativeChainCollector: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var chain: [Data] = []

    var certificates: [Data] { lock.withLock { chain } }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        lock.withLock { chain = certificates.map { SecCertificateCopyData($0) as Data } }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
