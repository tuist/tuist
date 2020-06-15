import TSCBasic
import XCTest
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class CertificateParserIntegrationTests: TuistTestCase {
    var subject: CertificateParser!

    override func setUp() {
        super.setUp()

        subject = CertificateParser()
    }

    override func tearDown() {
        super.tearDown()

        subject = nil
    }

    func test_parse_certificate() throws {
        // Given
        let currentDirectory = AbsolutePath(#file.replacingOccurrences(of: "file://", with: "")).removingLastComponent()
        let publicKey = currentDirectory.appending(component: "Target.Debug.cer")
        let privateKey = currentDirectory.appending(component: "Target.Debug.p12")
        let expectedCertificate = Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            developmentTeam: "QH95ER52SG",
            name: "Apple Development: Marek Fort (54GSF6G47V)",
            targetName: "Target",
            configurationName: "Debug",
            isRevoked: false
        )

        // When
        let certificate = try subject.parse(publicKey: publicKey, privateKey: privateKey)

        // Then
        XCTAssertEqual(certificate, expectedCertificate)
    }
}
