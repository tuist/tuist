import Foundation
import Security
import Testing

struct AtlasCertificateTrustTests {
    @Test func realPolicyDERIsDeniedAndUnrelatedKeysRemainAllowed() throws {
        let denied = try certificates("issuer-roots") + certificates("distrusted-intermediates")
        #expect(denied.count == 12)
        #expect(try Set(denied.map(AtlasCertificateTrust.spkiHash)) == AtlasCertificateTrust.blockedSPKIHashes)
        for certificate in denied {
            #expect(!AtlasCertificateTrust.isAllowed(derCertificate: certificate))
        }
        let allowed = try certificates("positive-isrg-root-x1") + certificates("positive-isrg-r11")
        #expect(allowed.count == 2)
        for certificate in allowed {
            #expect(AtlasCertificateTrust.isAllowed(derCertificate: certificate))
        }
    }

    private func certificates(_ name: String) throws -> [Data] {
        let url = try #require(Bundle(for: NativeChainCollector.self).url(forResource: name, withExtension: "pem"))
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().map { block in
                let base64 = try #require(block.components(separatedBy: "-----END CERTIFICATE-----").first)
                return try #require(Data(base64Encoded: base64, options: .ignoreUnknownCharacters))
            }
    }

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
    func acceptedNativeConstructedPathKeysAreRejectedByActualSession() async throws {
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
        #expect(chain.count >= 3)
        for certificate in chain {
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

        // A key deny must never replace ordinary native chain/hostname checks.
        for address in ["https://wrong.host.badssl.com/", "https://expired.badssl.com/", "https://self-signed.badssl.com/"] {
            do {
                _ = try await protected.data(from: #require(URL(string: address)))
                Issue.record("Ordinary native certificate validation was bypassed")
            } catch {
                let error = error as NSError
                #expect(error.domain == NSURLErrorDomain)
                #expect([
                    URLError.cancelled.rawValue,
                    URLError.serverCertificateHasBadDate.rawValue,
                    URLError.serverCertificateUntrusted.rawValue,
                    URLError.serverCertificateHasUnknownRoot.rawValue
                ].contains(error.code), "Expected native certificate rejection, got \(error.code)")
            }
        }
        let (_, restoredResponse) = try await protected.data(from: url)
        #expect((restoredResponse as? HTTPURLResponse)?.statusCode == 200)
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
