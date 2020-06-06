import XCTest
import TSCBasic
import TuistCore
@testable import TuistSupportTesting
@testable import TuistSigning

final class SigningLinterTests: TuistUnitTestCase {
    var subject: SigningLinter!
    
    override func setUp() {
        super.setUp()
        
        subject = SigningLinter()
    }
    
    override func tearDown() {
        super.tearDown()
        
        subject = nil
    }
    
    func test_lint_when_development_team_and_team_id_mismatch() {
        // Given
        let certificate = Certificate.test(developmentTeam: "TeamA")
        let provisioningProfile = ProvisioningProfile.test(teamId: "TeamB")
        let expectedIssues = [
            LintingIssue(
                reason: """
                Certificate \(certificate.name)'s development team \(certificate.developmentTeam) does not correspond to \(provisioningProfile.teamId).
                Make sure they are the same.
                """,
                severity: .error
            )
        ]
        
        // When
        let got = subject.lint(certificate: certificate, provisioningProfile: provisioningProfile)
        
        // Then
        XCTAssertEqual(got, expectedIssues)
    }
    
    func test_lint_when_certificate_is_revoked() {
        // Given
        let certificate = Certificate.test(isRevoked: true)
        let expectedIssues = [
            LintingIssue(
                reason: "Certificate \(certificate.name) is revoked. Create a new one and replace it to resolve the issue.",
                severity: .warning
            )
        ]
        
        // When
        let got = subject.lint(certificate: certificate)
        
        // Then
        XCTAssertEqual(got, expectedIssues)
    }
}
