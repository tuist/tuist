import Foundation
import Path

/// The type of a Swift Package described by `PackageInfo`.
public enum PackageType: Equatable, Codable {
    /// A local Swift package.
    case local
    /// A remote Swift package.
    case remote(artifactPaths: [String: AbsolutePath])
}
