import Foundation

/// The structure defining the output schema of an Swift package.
public struct PackageOutput: Codable, Equatable {
    
    /// The type of Swift package.
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
    
    /// Factory function to convert an internal graph package to the output type.
    public static func from(_ package: Package) -> PackageOutput {
        switch package {
        case .remote(let url, _):
            return PackageOutput(kind: PackageOutput.PackageKind.remote, path: url)
        case .local(let path):
            return PackageOutput(kind: PackageOutput.PackageKind.local, path: path.pathString)
        }
    }
}
