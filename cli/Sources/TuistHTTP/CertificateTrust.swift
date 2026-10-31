import Crypto
import Dispatch
import Foundation
#if canImport(Security)
    @preconcurrency import Security
#endif

public enum CertificateTrust {
    /// Checked against infra/certificate-trust/policy.json, not certificate subjects.
    static let blockedSPKIHashes: Set<String> = [
        "8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782",
        "bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3",
        "ebed6475c2c2d80fcb199f3fe8dd6e6b3ce60b77eb15d4e42c3dec0c6f5b5105",
        "49dd353dc2b919a3770645117d0e60c16115e7d1bc259eefe734b00ea434fe5f",
        "e0254c7fcdc265e2f0f8a428dabb75ab4ae039b4872d62f5ee57f0877d5a8a41",
        "5c0660a2b164910d8ff589c18e14552e9e0ec237dcefe2cb736d41a4811f81a0",
        "43bffa19d6ef651451f6841e019931e96f6f2eaeff28ab4b6f1ce4576de2717b",
        "63ecefee431d49523bc1136c4e72d0206a477086caf606cd5cf025686c109cf8",
        "ec4ffa1ad0ac88081314b7aaffef6a91f97cd57291bb5ba686c5415f5eb4f6b6",
        "92c063d67e8f14db71d288e11266ffdaf69cbf115f7bab14f3bc2f68d25e0e30",
        "c619e4780ed8e0abeda24ad732567de4383a7ea941338f6d1a7d1b49ac792fe9",
        "0a6c2b2ca5b364207954171987ac9d2178561569d8205457e77ca90c32ede282",
    ]

    #if canImport(Security)
        static func isAllowed(_ certificate: SecCertificate) -> Bool {
            isAllowed(derCertificate: SecCertificateCopyData(certificate) as Data)
        }

        private static let validationQueue = DispatchQueue(label: "dev.tuist.certificate-trust")

        /// Performs Apple's normal SSL/hostname validation, followed by the key deny,
        /// without blocking a networking event loop. Additional denies only restrict policy.
        public static func evaluateTLS(
            certificateChain: [Data],
            hostname: String,
            additionalAnchors: [Data],
            additionalBlockedSPKIHashes: Set<String> = [],
            completion: @escaping @Sendable (Bool) -> Void
        ) {
            let certificates = certificateChain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            let anchors = additionalAnchors.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            guard !certificates.isEmpty, certificates.count == certificateChain.count,
                  anchors.count == additionalAnchors.count
            else { completion(false); return }
            let policy = SecPolicyCreateSSL(true, hostname as CFString)
            var trust: SecTrust?
            guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess,
                  let trust,
                  TLSValidator.configure(
                      trust,
                      addingAdditionalAnchors: anchors,
                      additionalBlockedSPKIHashes: additionalBlockedSPKIHashes
                  )
            else { completion(false); return }
            // Security requires invocation and completion on the supplied queue.
            validationQueue.async {
                let result = SecTrustEvaluateAsyncWithError(trust, validationQueue) { trust, valid, _ in
                    completion(valid && TLSValidator.isAllowedChain(
                        trust,
                        additionalBlockedSPKIHashes: additionalBlockedSPKIHashes
                    ))
                }
                if result != errSecSuccess { completion(false) }
            }
        }
    #endif

    /// An additional key restriction, not a certificate or hostname verifier.
    /// Apply only alongside ordinary TLS verification.
    public static func isAllowed(derCertificate: Data, additionalBlockedSPKIHashes: Set<String> = []) -> Bool {
        guard let hash = try? spkiHash(derCertificate) else { return false }
        return !blockedSPKIHashes.contains(hash) && !additionalBlockedSPKIHashes.contains(hash)
    }

    static func spkiHash(_ certificate: Data) throws -> String {
        let bytes = Array(certificate)
        var certificateReader = DERReader(bytes: bytes, range: bytes.indices)
        let sequence = try certificateReader.read(tag: 0x30)
        guard certificateReader.isAtEnd else { throw InvalidCertificate() }
        var sequenceReader = DERReader(bytes: bytes, range: sequence.content)
        let tbs = try sequenceReader.read(tag: 0x30)
        _ = try sequenceReader.read(tag: 0x30)
        _ = try sequenceReader.read(tag: 0x03)
        guard sequenceReader.isAtEnd else { throw InvalidCertificate() }
        var reader = DERReader(bytes: bytes, range: tbs.content)
        if reader.nextTag == 0xA0 { _ = try reader.read(tag: 0xA0) }
        _ = try reader.read(tag: 0x02) // Serial number.
        for _ in 0 ..< 4 {
            _ = try reader.read(tag: 0x30)
        } // Signature, issuer, validity, subject.
        let spki = try reader.read(tag: 0x30)
        return SHA256.hash(data: Data(bytes[spki.whole])).map { String(format: "%02x", $0) }.joined()
    }

    private struct InvalidCertificate: Error {}

    private struct DERReader {
        let bytes: [UInt8]
        private let end: Int
        private var offset: Int

        init(bytes: [UInt8], range: Range<Int>) {
            self.bytes = bytes
            offset = range.lowerBound
            end = range.upperBound
        }

        var isAtEnd: Bool { offset == end }
        var nextTag: UInt8? { offset < end ? bytes[offset] : nil }

        mutating func read(tag: UInt8) throws -> (whole: Range<Int>, content: Range<Int>) {
            let start = offset
            guard end - offset >= 2, bytes[offset] == tag else { throw InvalidCertificate() }
            offset += 1
            let first = Int(bytes[offset])
            offset += 1
            var length = first
            if first >= 0x80 {
                let count = first & 0x7F
                guard count > 0, count <= 4, end - offset >= count, bytes[offset] != 0 else {
                    throw InvalidCertificate()
                }
                length = 0
                for _ in 0 ..< count {
                    length = length * 256 + Int(bytes[offset])
                    offset += 1
                }
                guard length >= 128 else { throw InvalidCertificate() }
            }
            guard length <= end - offset else { throw InvalidCertificate() }
            let content = offset ..< offset + length
            offset += length
            return (start ..< offset, content)
        }
    }
}
