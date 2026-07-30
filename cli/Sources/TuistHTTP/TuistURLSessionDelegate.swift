import Foundation
import TuistLogging

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(TuistHAR)
    import TuistHAR
#endif

#if canImport(Security)
    import Security

    /// A URLSession delegate that trusts an additional set of CA certificates on top of
    /// the system root store, while preserving HAR metrics collection.
    ///
    /// The system keychain is still consulted: the custom anchors are *added* to the
    /// existing trust evaluation and `SecTrustSetAnchorCertificatesOnly` is set to
    /// `false`, so the system root store keeps validating normally. This lets teams run
    /// a self-hosted Tuist/Kura server with a private CA on hosts where installing a
    /// trusted root in the System keychain isn't practical (for example headless CI).
    final class TuistURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let additionalCertificates: [SecCertificate]

        init(additionalCertificates: [SecCertificate]) {
            self.additionalCertificates = additionalCertificates
            super.init()
        }

        func urlSession(
            _: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            if TLSValidator.evaluate(trust, addingAdditionalAnchors: additionalCertificates) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }

        #if canImport(TuistHAR)
            func urlSession(
                _ session: URLSession,
                task: URLSessionTask,
                didFinishCollecting metrics: URLSessionTaskMetrics
            ) {
                // Forward to the shared metrics delegate so HAR recording keeps working
                // when a session uses a custom-trust delegate.
                URLSessionMetricsDelegate.shared.urlSession(session, task: task, didFinishCollecting: metrics)
            }
        #endif
    }

    enum TLSValidator {
        /// Evaluates `trust`, optionally adding `additionalAnchors` (for example a private
        /// CA) on top of the system root store before evaluation. Returns `true` if the
        /// server is trusted. The system root store is never replaced: extra anchors are
        /// additive (`SecTrustSetAnchorCertificatesOnly(trust, false)`).
        static func evaluate(_ trust: SecTrust, addingAdditionalAnchors anchors: [SecCertificate]) -> Bool {
            if !anchors.isEmpty {
                SecTrustSetAnchorCertificates(trust, anchors as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, false)
            }
            var error: CFError?
            return SecTrustEvaluateWithError(trust, &error)
        }
    }

    /// Loads DER `SecCertificate` objects from a PEM bundle (one or more concatenated
    /// `-----BEGIN CERTIFICATE-----` blocks) or a single DER file.
    enum CACertificateLoader {
        /// Returns the certificates in the bundle, or `nil` (with a logged warning) if the
        /// file can't be read or contains no parseable certificates. Returning `nil` lets
        /// the caller fall back to the default session rather than failing hard.
        static func load(from path: String) -> [SecCertificate]? {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url) else {
                Logger.current
                    .warning(
                        "Could not read the custom CA certificate bundle at '\(path)'. TLS will use the system trust store only."
                    )
                return nil
            }
            let certificates = parse(from: data)
            if certificates.isEmpty {
                Logger.current
                    .warning("No certificates could be parsed from '\(path)'. TLS will use the system trust store only.")
                return nil
            }
            return certificates
        }

        /// Parses certificates from PEM or DER data.
        static func parse(from data: Data) -> [SecCertificate] {
            let base64Blocks = pemBlocks(from: data)
            let derBlocks: [Data]
            if base64Blocks.isEmpty {
                // Not PEM: treat the whole blob as a single DER certificate.
                derBlocks = [data]
            } else {
                derBlocks = base64Blocks.compactMap { Data(base64Encoded: $0) }
            }
            return derBlocks.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        }

        private static let beginMarker = "-----BEGIN CERTIFICATE-----"
        private static let endMarker = "-----END CERTIFICATE-----"

        /// Extracts the base64 body of each PEM certificate block. Returns an empty array
        /// when the data isn't PEM (for example a raw DER file).
        private static func pemBlocks(from data: Data) -> [String] {
            guard let text = String(data: data, encoding: .utf8),
                  text.contains(beginMarker)
            else { return [] }

            var blocks: [String] = []
            var searchRange = text.startIndex ..< text.endIndex
            while let beginRange = text.range(of: beginMarker, range: searchRange),
                  let endRange = text.range(of: endMarker, range: beginRange.upperBound ..< text.endIndex)
            {
                let base64 = text[beginRange.upperBound ..< endRange.lowerBound]
                    .filter { !$0.isWhitespace }
                blocks.append(String(base64))
                searchRange = endRange.upperBound ..< text.endIndex
            }
            return blocks
        }
    }

#endif
