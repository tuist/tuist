import Foundation
import TSCBasic
import TuistSupport

enum ProvisioningProfileParserError: FatalError {
    var type: ErrorType {
        switch self {
        case .valueNotFound, .invalidFormat:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .valueNotFound(value, path):
            return "Could not find \(value). Check if the provided xml at \(path.pathString) is valid."
        case let .invalidFormat(provisioningProfile):
            return "Provisioning Profile \(provisioningProfile) is in invalid format. Please name your certificates in the following way: Target.Configuration.mobileprovision"
        }
    }

    case valueNotFound(String, AbsolutePath)
    case invalidFormat(String)
}

protocol ProvisioningProfileParsing {
    func parse(at path: AbsolutePath) throws -> ProvisioningProfile
}

final class ProvisioningProfileParser: ProvisioningProfileParsing {
    private let securityController: SecurityControlling

    init(securityController: SecurityControlling = SecurityController()) {
        self.securityController = securityController
    }

    func parse(at path: AbsolutePath) throws -> ProvisioningProfile {
        let provisioningProfileComponents = path.basenameWithoutExt.components(separatedBy: ".")
        guard provisioningProfileComponents.count == 2 else { throw ProvisioningProfileParserError.invalidFormat(path.pathString) }
        let targetName = provisioningProfileComponents[0]
        let configurationName = provisioningProfileComponents[1]

        let unencryptedProvisioningProfile = try securityController.decodeFile(at: path)
        let plistData = Data(unencryptedProvisioningProfile.utf8)
        let provisioningProfileContent = try PropertyListDecoder().decode(ProvisioningProfile.Content.self, from: plistData)

        let developerCertificateFingerprints = try provisioningProfileContent.developerCertificates.map { (data) throws -> String in
            let certificateParser = CertificateParser()
            return try certificateParser.parseFingerPrint(developerCertificate: data)
        }

        return ProvisioningProfile(path: path,
                                   name: provisioningProfileContent.name,
                                   targetName: targetName,
                                   configurationName: configurationName,
                                   uuid: provisioningProfileContent.uuid,
                                   teamId: provisioningProfileContent.teamId,
                                   appId: provisioningProfileContent.appId,
                                   appIdName: provisioningProfileContent.appIdName,
                                   applicationIdPrefix: provisioningProfileContent.applicationIdPrefix,
                                   platforms: provisioningProfileContent.platforms,
                                   expirationDate: provisioningProfileContent.expirationDate,
                                   developerCertificateFingerprints: developerCertificateFingerprints)
    }
}
