import Foundation
import TSCBasic
import TuistSupport

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
        teamId = try container.decode(DecodingFirst<String>.self, forKey: .teamIds).wrappedValue
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
