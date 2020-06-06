import TSCBasic
import Foundation

/// Model of a provisioning profile
struct ProvisioningProfile: Equatable {
    /// Path to the provisioning profile
    var path: AbsolutePath?
    let name: String
    let targetName: String
    let configurationName: String
    let uuid: String
    let teamId: String
    let appId: String
    let appIdName: String
    let applicationIdPrefix: [String]
    let platforms: [String]
    let expirationDate: Date
    
    init(path: AbsolutePath? = nil,
         name: String,
         targetName: String,
         configurationName: String,
         uuid: String,
         teamId: String,
         appId: String,
         appIdName: String,
         applicationIdPrefix: [String],
         platforms: [String],
         expirationDate: Date) {
        self.path = path
        self.name = name
        self.targetName = targetName
        self.configurationName = configurationName
        self.uuid = uuid
        self.teamId = teamId
        self.appId = appId
        self.appIdName = appIdName
        self.applicationIdPrefix = applicationIdPrefix
        self.platforms = platforms
        self.expirationDate = expirationDate
    }
}

extension ProvisioningProfile: Decodable {
    private struct Entitlements: Decodable {
        let appId: String
        
        private enum CodingKeys: String, CodingKey {
            case appId = "application-identifier"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            appId = try container.decode(String.self, forKey: .appId)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case uuid = "UUID"
        case teamIds = "TeamIdentifier"
        case appIdName = "AppIDName"
        case applicationIdPrefix = "ApplicationIdentifierPrefix"
        case platforms = "Platform"
        case entitlements = "Entitlements"
        case expirationDate = "ExpirationDate"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        uuid = try container.decode(String.self, forKey: .uuid)
        let teamIds = try container.decode([String].self, forKey: .teamIds)
        guard
            let teamId = teamIds.first
            else { throw DecodingError.valueNotFound(String.self, DecodingError.Context(codingPath: container.codingPath,
                                                                                        debugDescription: "Array of teamID must be non-empty"))
        }
        self.teamId = teamId
        appIdName = try container.decode(String.self, forKey: .appIdName)
        applicationIdPrefix = try container.decode([String].self, forKey: .applicationIdPrefix)
        platforms = try container.decode([String].self, forKey: .platforms)
        let entitlements = try container.decode(Entitlements.self, forKey: .entitlements)
        appId = entitlements.appId
        expirationDate = try container.decode(Date.self, forKey: .expirationDate)
        
        let nameComponents = name.components(separatedBy: ".")
        guard
            let targetName = nameComponents.first,
            let configurationName = nameComponents.last
            else { throw DecodingError.dataCorruptedError(forKey: .name,
                                                          in: container,
                                                          debugDescription: "Provisioning profile's name is not in format {Target}.{Configuration}")
        }
        self.targetName = targetName
        self.configurationName = configurationName
    }
}
