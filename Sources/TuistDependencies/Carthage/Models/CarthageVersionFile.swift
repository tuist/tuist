import Foundation
import TuistGraph

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
    
    /// Returns all products.
    var allProducts: [Product] {
        iOS + macOS + watchOS + tvOS
    }
}

// MARK: - Models

extension CarthageVersionFile {
    struct Product: Decodable, Equatable {
        let swiftToolchainVersion: String
        let hash: String
        let name: String
        let container: String
        let identifier: String
        
        /// Returns architectures the product is built for.
        var architectures: [BinaryArchitecture] {
            // example identifier: `ios-arm64_i386_x86_64-simulator`
            identifier
                .components(separatedBy: "-")[1]
                .replacingOccurrences(of: "x86_64", with: "x8664")
                .replacingOccurrences(of: "arm64_32", with: "arm6432")
                .components(separatedBy: ["_"])
                .map { $0 == "x8664" ? "x86_64" : $0  }
                .map { $0 == "arm6432" ? "arm64_32" : $0 }
                .compactMap { BinaryArchitecture(rawValue: $0) }
        }
    }
}
