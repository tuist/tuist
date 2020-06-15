import Foundation
import TSCBasic
import TuistSupport

enum ProvisioningProfileParserError: FatalError {
    var type: ErrorType {
        switch self {
        case .valueNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .valueNotFound(value, path):
            return "Could not find \(value). Check if the provided xml at \(path.pathString) is valid."
        }
    }

    case valueNotFound(String, AbsolutePath)
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
        let unencryptedProvisioningProfile = try securityController.decodeFile(at: path)
        let plistData = Data(unencryptedProvisioningProfile.utf8)
        let provisioningProfile = try PropertyListDecoder().decode(ProvisioningProfile.self, from: plistData)
        return ProvisioningProfile(path: path,
                                   name: provisioningProfile.name,
                                   targetName: provisioningProfile.targetName,
                                   configurationName: provisioningProfile.configurationName,
                                   uuid: provisioningProfile.uuid,
                                   teamId: provisioningProfile.teamId,
                                   appId: provisioningProfile.appId,
                                   appIdName: provisioningProfile.appIdName,
                                   applicationIdPrefix: provisioningProfile.applicationIdPrefix,
                                   platforms: provisioningProfile.platforms,
                                   expirationDate: provisioningProfile.expirationDate)
    }
}
