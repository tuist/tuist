import Foundation

/// A model that represents a `Package.swift` manifest file.
public struct PackageInfo: Equatable, Codable {
    public let name: String
    public let platforms: [Platform]
    public let toolsVersion: ToolsVersion
    public let cLanguageStandard: String?
    public let cxxLanguageStandard: String?
    
    // add later:
    //
    // "dependencies"
    // "pkgConfig"
    // "products"
    // "providers"
    // "swiftLanguageVersions"
    // "targets"
}

// MARK: - Models

extension PackageInfo {
    public struct Platform: Equatable, Codable {
        public let platformName: String
        public let version: String
        
        // add later:
        //
        // "options"
    }
    
    public struct ToolsVersion: Equatable, Codable {
        enum CodingKeys: String, CodingKey {
            case version = "_version"
        }
        
        public let version: String
    }
}
