import Foundation
import Path

/// The type of a Swift Package described by `PackageInfo`.
public enum PackageType: Equatable, Codable {
    /// A local Swift package.
    case local
    /// The type of a remote Swift Package.
    case remote(artifactPaths: [String: AbsolutePath])
}
