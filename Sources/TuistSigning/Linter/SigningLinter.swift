import Foundation
import TuistCore
import TuistGraph

protocol SigningLinting {
    func lint(certificate: Certificate, provisioningProfile: ProvisioningProfile) -> [LintingIssue]
    func lint(certificate: Certificate) -> [LintingIssue]
    func lint(provisioningProfile: ProvisioningProfile, target: Target) -> [LintingIssue]
}

final class SigningLinter: SigningLinting {
    func lint(certificate: Certificate, provisioningProfile: ProvisioningProfile) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if certificate.developmentTeam != provisioningProfile.teamId {
            let reason = """
            Certificate \(certificate.name)'s development team \(certificate
                .developmentTeam) does not correspond to \(provisioningProfile.teamId).
            Make sure they are the same.
            """
            issues.append(LintingIssue(reason: reason, severity: .error))
        }

        return issues
    }

    func lint(certificate: Certificate) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if certificate.isRevoked {
            issues.append(LintingIssue(
                reason: "Certificate \(certificate.name) is revoked. Create a new one and replace it to resolve the issue.",
                severity: .warning
            ))
        }
        return issues
    }

    func lint(provisioningProfile: ProvisioningProfile, target: Target) -> [LintingIssue] {
        let appId = provisioningProfile.teamId + "." + target.bundleId
        let invalidProvisioningProfileIssue = LintingIssue(
            reason: """
            App id \(provisioningProfile.appId) does not correspond to \(provisioningProfile.teamId).\(target
                .bundleId). Make sure the provisioning profile has been added to the right target.
            """,
            severity: .error
        )
        let buildSettingRegex = "\\$[\\({](.*)[\\)}]"

        var issues: [LintingIssue] = []

        if target.bundleId.matches(pattern: buildSettingRegex) {
            return issues
        } else if provisioningProfile.appId.last == "*" {
            if !appId.hasPrefix(provisioningProfile.appId.dropLast()) {
                issues.append(invalidProvisioningProfileIssue)
            }
        } else {
            if provisioningProfile.appId != provisioningProfile.teamId + "." + target.bundleId {
                issues.append(invalidProvisioningProfileIssue)
            }
        }

        return issues
    }
}
