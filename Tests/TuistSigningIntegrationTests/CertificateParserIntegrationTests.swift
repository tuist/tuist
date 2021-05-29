import TSCBasic
import XCTest
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class CertificateParserIntegrationTests: TuistTestCase {
    var certificateParser: CertificateParser!

    override func setUp() {
        super.setUp()

        certificateParser = CertificateParser()
    }

    override func tearDown() {
        super.tearDown()

        certificateParser = nil
    }

    func test_parse_certificate() throws {
        // Given
        let currentDirectory = AbsolutePath(#file.replacingOccurrences(of: "file://", with: "")).removingLastComponent()
        let publicKey = currentDirectory.appending(component: "Target.Debug.cer")
        let privateKey = currentDirectory.appending(component: "Target.Debug.p12")
        let expectedCertificate = Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            fingerprint: "SHA1 Fingerprint=80:B8:6E:55:1D:8E:F2:38:CD:95:3C:7E:72:3B:DB:B1:A5:B0:5D:60",
            developmentTeam: "QH95ER52SG",
            name: "Apple Development: Marek Fort (54GSF6G47V)",
            isRevoked: false
        )

        // When
        let certificate = try certificateParser.parse(publicKey: publicKey, privateKey: privateKey)

        // Then
        XCTAssertEqual(certificate, expectedCertificate)
    }
}
