import TSCBasic
import XCTest
@testable import TuistSigning
@testable import TuistSupportTesting

final class CertificateParserTests: TuistUnitTestCase {
    var subject: CertificateParser!

    override func setUp() {
        super.setUp()

        subject = CertificateParser()
    }

    override func tearDown() {
        super.tearDown()

        subject = nil
    }

    func test_name_parsing_fails_when_not_present() throws {
        // Given
        let publicKey = try temporaryPath().appending(component: "Target.Debug.p12")
        let privateKey = try temporaryPath()
        let subjectOutput = "subject= /UID=VD55TKL3V6/OU=QH95ER52SG/O=Name/C=US\n"
        system.succeedCommand(
            "openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-subject",
            output: subjectOutput
        )

        // When
        XCTAssertThrowsSpecific(
            try subject.parse(publicKey: publicKey, privateKey: privateKey),
            CertificateParserError.nameParsingFailed(publicKey, subjectOutput)
        )
    }

    func test_development_team_fails_when_not_present() throws {
        // Given
        let publicKey = try temporaryPath().appending(component: "Target.Debug.p12")
        let privateKey = try temporaryPath()
        let subjectOutput = "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/O=Name/C=US\n"
        system.succeedCommand(
            "openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-subject",
            output: subjectOutput
        )

        // When
        XCTAssertThrowsSpecific(
            try subject.parse(publicKey: publicKey, privateKey: privateKey),
            CertificateParserError.developmentTeamParsingFailed(publicKey, subjectOutput)
        )
    }

    func test_throws_invalid_name_when_wrong_format() throws {
        // Given
        let publicKey = try temporaryPath()
        let privateKey = try temporaryPath()

        // When
        XCTAssertThrowsSpecific(
            try subject.parse(publicKey: publicKey, privateKey: privateKey),
            CertificateParserError.invalidFormat(publicKey.pathString)
        )
    }

    func test_parsing_succeeds() throws {
        // Given
        let publicKey = try temporaryPath().appending(component: "Target.Debug.p12")
        let privateKey = try temporaryPath()
        let subjectOutput = "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/OU=QH95ER52SG/O=Name/C=US\n"
        system.succeedCommand(
            "openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-subject",
            output: subjectOutput
        )
        let expectedCertificate = Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            developmentTeam: "QH95ER52SG",
            name: "Apple Development: Name (54GSF6G47V)",
            targetName: "Target",
            configurationName: "Debug",
            isRevoked: false
        )

        // When
        let certificate = try subject.parse(publicKey: publicKey, privateKey: privateKey)

        // Then
        XCTAssertEqual(certificate, expectedCertificate)
    }

    func test_parsing_succeeds_with_different_format() throws {
        // Given
        let publicKey = try temporaryPath().appending(component: "Target.Debug.p12")
        let privateKey = try temporaryPath()
        let subjectOutput = "subject=UID = VD55TKL3V6, CN = Apple Development: Name (54GSF6G47V), OU = QH95ER52SG, O = Name, C = US"
        system.succeedCommand(
            "openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-subject",
            output: subjectOutput
        )
        let expectedCertificate = Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            developmentTeam: "QH95ER52SG",
            name: "Apple Development: Name (54GSF6G47V)",
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
