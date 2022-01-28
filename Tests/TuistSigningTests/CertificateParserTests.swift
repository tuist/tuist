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
        subject = nil
        super.tearDown()
    }

    func test_name_parsing_fails_when_not_present() throws {
        // Given
        let publicKey = try temporaryPath().appending(component: "Target.Debug.p12")
        let privateKey = try temporaryPath()
        let subjectOutput = "subject= /UID=VD55TKL3V6/OU=QH95ER52SG/O=Name/C=US\n"
        system.succeedCommand(
            ["openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-subject"],
            output: subjectOutput
        )
        let fingerprintOutput = "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/OU=QH95ER52SG/O=Name/C=US\n"
        system.succeedCommand(
            ["openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-fingerprint"],
            output: fingerprintOutput
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
            ["openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-subject"],
            output: subjectOutput
        )
        let fingerprintOutput = "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/OU=QH95ER52SG/O=Name/C=US\n"
        system.succeedCommand(
            ["openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-fingerprint"],
            output: fingerprintOutput
        )

        // When
        XCTAssertThrowsSpecific(
            try subject.parse(publicKey: publicKey, privateKey: privateKey),
            CertificateParserError.developmentTeamParsingFailed(publicKey, subjectOutput)
        )
    }

    func test_parsing_succeeds() throws {
        // Given
        let publicKey = try temporaryPath().appending(component: "Target.Debug.p12")
        let privateKey = try temporaryPath()
        let subjectOutput = "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/OU=QH95ER52SG/O=Name/C=US\n"
        system.succeedCommand(
            ["openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-subject"],
            output: subjectOutput
        )
        let fingerprintOutput = "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/OU=QH95ER52SG/O=Name/C=US\n"
        system.succeedCommand(
            ["openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-fingerprint"],
            output: fingerprintOutput
        )
        let expectedCertificate = Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            fingerprint: "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/OU=QH95ER52SG/O=Name/C=US",
            developmentTeam: "QH95ER52SG",
            name: "Apple Development: Name (54GSF6G47V)",
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
        let subjectOutput =
            "subject=UID = VD55TKL3V6, CN = Apple Development: Name (54GSF6G47V), OU = QH95ER52SG, O = Name, C = US"
        system.succeedCommand(
            ["openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-subject"],
            output: subjectOutput
        )
        let fingerprintOutput = "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/OU=QH95ER52SG/O=Name/C=US\n"
        system.succeedCommand(
            ["openssl", "x509", "-inform", "der", "-in", publicKey.pathString, "-noout", "-fingerprint"],
            output: fingerprintOutput
        )
        let expectedCertificate = Certificate(
            publicKey: publicKey,
            privateKey: privateKey,
            fingerprint: "subject= /UID=VD55TKL3V6/CN=Apple Development: Name (54GSF6G47V)/OU=QH95ER52SG/O=Name/C=US",
            developmentTeam: "QH95ER52SG",
            name: "Apple Development: Name (54GSF6G47V)",
            isRevoked: false
        )

        // When
        let certificate = try subject.parse(publicKey: publicKey, privateKey: privateKey)

        // Then
        XCTAssertEqual(certificate, expectedCertificate)
    }

    func test_sanitizeEncoding() {
        // Given
        let oneWrongEncoding = "test \\xC3\\xA4 something"
        let twoWrongEncodings = "test \\xC3\\xA4 something \\xC2\\xB6 something else"
        let twoWrongEncodingsInARow = "test \\xC3\\xA4\\xC2\\xB2 something"
        let oneWrongEncodingWithMixedCapitalization = "test \\xc3\\xA4 something"

        // Then
        XCTAssertEqual(oneWrongEncoding.sanitizeEncoding(), "test ä something")
        XCTAssertEqual(twoWrongEncodings.sanitizeEncoding(), "test ä something ¶ something else")
        XCTAssertEqual(twoWrongEncodingsInARow.sanitizeEncoding(), "test ä² something")
        XCTAssertEqual(oneWrongEncodingWithMixedCapitalization.sanitizeEncoding(), "test ä something")
    }
}
