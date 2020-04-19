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
        guard
            let provisioningProfileDict: [String: Any] = try PropertyListSerialization.propertyList(from: plistData,
                                                               options: .mutableContainersAndLeaves,
                                                               format: nil) as? [String: Any],
            let name = provisioningProfileDict["Name"] as? String,
            let uuid = provisioningProfileDict["UUID"] as? String
        else {
                fatalError()
        }
        
        let nameComponents = name.components(separatedBy: ".")
        guard
            let targetName = nameComponents.first,
            let configurationName = nameComponents.last
        else { fatalError() }
        
        return ProvisioningProfile(name: name,
                                   targetName: targetName,
                                   configurationName: configurationName,
                                   uuid: uuid)
    }
}
