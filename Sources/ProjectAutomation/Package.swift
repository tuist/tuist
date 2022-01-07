import Foundation

/// The structure defining the output schema of the Swift package.
public struct Package: Codable, Equatable {
    /// The type of the Swift package.
    public enum PackageKind: String, Codable {
        case remote
        case local
    }

    /// The type of the package.
    public let kind: PackageKind

    /// The path of the package. In the case of local packages, the path is an absolute path to the package directory.
    /// In the case of a remote package, the value is the URL of the package.
    public let path: String

    public init(kind: PackageKind, path: String) {
        self.kind = kind
        self.path = path
    }
}
