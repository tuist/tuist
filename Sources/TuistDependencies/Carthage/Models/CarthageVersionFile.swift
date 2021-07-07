import Foundation
import TuistGraph

/// A model that represents the `Carthage` version file.
/// Reference: https://github.com/Carthage/Carthage/blob/master/Documentation/VersionFile.md#version-files
struct CarthageVersionFile: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case iOS
        case macOS = "Mac"
        case watchOS
        case tvOS
    }

    let iOS: [Product]?
    let macOS: [Product]?
    let watchOS: [Product]?
    let tvOS: [Product]?

    /// Returns all products.
    var allProducts: [Product] {
        [iOS, macOS, watchOS, tvOS]
            .compactMap { $0 }
            .flatMap { $0 }
    }
}

// MARK: - Models

extension CarthageVersionFile {
    struct Product: Decodable, Equatable {
        let name: String
        let container: String?
    }
}
