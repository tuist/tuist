import TSCBasic
import TuistCore
import TuistGraph
import XCTest
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class SigningLinterTests: TuistUnitTestCase {
    var subject: SigningLinter!

    override func setUp() {
        super.setUp()

        subject = SigningLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_when_development_team_and_team_id_mismatch() {
        // Given
        let certificate = Certificate.test(developmentTeam: "TeamA")
        let provisioningProfile = ProvisioningProfile.test(teamId: "TeamB")
        let expectedIssues = [
            LintingIssue(
                reason: """
                Certificate \(certificate.name)'s development team \(certificate
                    .developmentTeam) does not correspond to \(provisioningProfile.teamId).
                Make sure they are the same.
                """,
                severity: .error
            ),
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
            ),
        ]

        // When
        let got = subject.lint(certificate: certificate)

        // Then
        XCTAssertEqual(got, expectedIssues)
    }

    func test_lint_when_provisioning_profile_and_app_id_match() {
        // Given
        let provisioningProfile = ProvisioningProfile.test(
            teamId: "team",
            appId: "team.io.tuist"
        )
        let target = Target.test(bundleId: "io.tuist")

        // When
        let got = subject.lint(provisioningProfile: provisioningProfile, target: target)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lint_when_provisioning_profile_and_app_id_mismatch() {
        // Given
        let provisioningProfile = ProvisioningProfile.test(
            teamId: "team",
            appId: "team.io.not-tuist"
        )
        let target = Target.test(bundleId: "io.tuist")

        // When
        let got = subject.lint(provisioningProfile: provisioningProfile, target: target)

        // Then
        XCTAssertEqual(
            got,
            [LintingIssue(
                reason: """
                App id \(provisioningProfile.appId) does not correspond to \(provisioningProfile.teamId).\(target
                    .bundleId). Make sure the provisioning profile has been added to the right target.
                """,
                severity: .error
            )]
        )
    }

    func test_lint_when_provisioning_profile_has_wildcard() {
        // Given
        let provisioningProfile = ProvisioningProfile.test(
            teamId: "team",
            appId: "team.io.*"
        )
        let target = Target.test(bundleId: "io.tuist")

        // When
        let got = subject.lint(provisioningProfile: provisioningProfile, target: target)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lint_when_provisioning_profile_has_wildcard_mismatch() {
        // Given
        let provisioningProfile = ProvisioningProfile.test(
            teamId: "team",
            appId: "team.not-io.*"
        )
        let target = Target.test(bundleId: "io.tuist")

        // When
        let got = subject.lint(provisioningProfile: provisioningProfile, target: target)

        // Then
        XCTAssertEqual(
            got,
            [LintingIssue(
                reason: """
                App id \(provisioningProfile.appId) does not correspond to \(provisioningProfile.teamId).\(target
                    .bundleId). Make sure the provisioning profile has been added to the right target.
                """,
                severity: .error
            )]
        )
    }

    func test_lint_when_bundle_id_is_derived_from_build_settings_using_parentheses_pattern() {
        // Given
        let provisioningProfile = ProvisioningProfile.test(
            teamId: "team",
            appId: "team.io.tuist"
        )
        let target = Target.test(bundleId: "$(PRODUCT_BUNDLE_IDENTIFIER)")

        // When
        let got = subject.lint(provisioningProfile: provisioningProfile, target: target)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lint_when_bundle_id_is_derived_from_build_settings_using_braces_pattern() {
        // Given
        let provisioningProfile = ProvisioningProfile.test(
            teamId: "team",
            appId: "team.io.tuist"
        )
        let target = Target.test(bundleId: "${PRODUCT_BUNDLE_IDENTIFIER}")

        // When
        let got = subject.lint(provisioningProfile: provisioningProfile, target: target)

        // Then
        XCTAssertEmpty(got)
    }
}
