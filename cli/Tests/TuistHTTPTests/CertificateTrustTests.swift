#if canImport(Security)
    import Foundation
    import Security
    import Testing
    import TuistTestSupport

    @testable import TuistHTTP

    @Suite
    struct CertificateTrustTests {
        @Test
        func rejects_all_twelve_keys_and_hashes_the_complete_DER_SPKI() throws {
            let certificates = try Self.certificates("issuer-roots") + Self.certificates("distrusted-intermediates")
            #expect(certificates.count == 12)
            let hashes = try Set(certificates.map { try CertificateTrust.spkiHash(SecCertificateCopyData($0) as Data) })
            #expect(hashes == CertificateTrust.blockedSPKIHashes)
            #expect(certificates.allSatisfy { !CertificateTrust.isAllowed($0) })
        }

        @Test
        func preserves_unrelated_RSA_root_and_intermediate_keys() throws {
            let certificates = try Self.certificates("positive-isrg-root-x1") + Self.certificates("positive-isrg-r11")
            #expect(certificates.count == 2)
            #expect(certificates.allSatisfy(CertificateTrust.isAllowed))
        }

        @Test(arguments: [Data(), Data([0x30, 0x80]), Data([0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF]), Data([0x30, 0x81, 0])])
        func refuses_malformed_truncated_or_indefinite_DER(data: Data) {
            #expect(throws: (any Error).self) { try CertificateTrust.spkiHash(data) }
        }

        private static func certificates(_ name: String) throws -> [SecCertificate] {
            let path = TestPaths.fixturesDirectory.appending(components: "CertificateTrust", "\(name).pem")
            return CACertificateLoader.parse(from: try Data(contentsOf: URL(fileURLWithPath: path.pathString)))
        }
    }
#endif
