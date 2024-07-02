import Foundation
import Path

/// The type of a Swift Package described by `PackageInfo`.
public enum PackageType: Equatable, Codable {
    /// The type of a local Swift Package. It means that the `Package.swift` file is in the local.
    case local
    /// The type of a remote Swift Package.
    case remote(artifactPaths: [String: AbsolutePath])
}
