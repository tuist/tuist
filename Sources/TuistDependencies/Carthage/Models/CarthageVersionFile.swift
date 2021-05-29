import Foundation

/// A model that represents the `Carhtage` version file.
/// Reference: https://github.com/Carthage/Carthage/blob/master/Documentation/VersionFile.md#version-files
struct CarthageVersionFile: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case commitish
        case iOS
        case macOS = "Mac"
        case watchOS
        case tvOS
    }
    
    let commitish: String
    let iOS: [Product]
    let macOS: [Product]
    let watchOS: [Product]
    let tvOS: [Product]
}

// MARK: - Models

extension CarthageVersionFile {
    struct Product: Decodable, Equatable {
        let swiftToolchainVersion: String
        let hash: String
        let name: String
        let container: String
        let identifier: String
    }
}
