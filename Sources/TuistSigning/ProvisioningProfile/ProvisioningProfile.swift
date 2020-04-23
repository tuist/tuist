import TSCBasic
import Foundation

struct ProvisioningProfile: Equatable {
    let path: AbsolutePath
    let name: String
    let targetName: String
    let configurationName: String
    let uuid: String
    let teamID: String
    let appID: String
    let appIDName: String
    let applicationIDPrefix: [String]
    let platforms: [String]
    let expirationDate: Date
}
