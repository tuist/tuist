import Foundation
import TuistGraph

/// A model that represents a `Package.swift` manifest file.
public struct PackageInfo: Equatable, Codable {
    public let name: String
    public let platforms: [PlatformInfo]
    public let toolsVersion: ToolsVersion
}

// MARK: - Helpers

extension PackageInfo {
    /// Returns a main scheme name from project that was generated using `swift package generate-xcodeproj` command.
    var schemeName: String {
        name + "-Package"
    }
    
    /// Returns platforms that the package supports.
    var supportedPlatforms: Set<Platform> {
        Set(platforms.compactMap(\.platform))
    }
}

// MARK: - Models

extension PackageInfo {
    public struct PlatformInfo: Equatable, Codable {
        public let platformName: String
        public let version: String
        
        /// Returns `TuistGraph.Platform` representation.
        var platform: Platform? {
            Platform(rawValue: platformName)
        }
    }
    
    public struct ToolsVersion: Equatable, Codable {
        enum CodingKeys: String, CodingKey {
            case version = "_version"
        }
        
        public let version: String
    }
}
