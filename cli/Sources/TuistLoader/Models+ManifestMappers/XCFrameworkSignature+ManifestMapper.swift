import ProjectDescription
import XcodeGraph

extension ProjectDescription.XCFrameworkSignature {
    static func from(_ signature: XcodeGraph.XCFrameworkSignature) -> Self {
        switch signature {
        case .unsigned:
            return .unsigned
        case let .selfSigned(fingerprint):
            return .selfSigned(fingerprint: fingerprint)
        case let .signedWithAppleCertificate(teamIdentifier, teamName):
            return .signedWithAppleCertificate(teamIdentifier: teamIdentifier, teamName: teamName)
        }
    }
}
