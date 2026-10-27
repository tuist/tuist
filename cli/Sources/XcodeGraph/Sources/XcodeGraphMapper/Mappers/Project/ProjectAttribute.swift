import Foundation

/// Attributes for project settings that can be retrieved from a `PBXProject`.
enum ProjectAttributeKey: String {
    case classPrefix = "CLASSPREFIX"
    case organization = "ORGANIZATIONNAME"
    case lastUpgradeCheck = "LastUpgradeCheck"
}
