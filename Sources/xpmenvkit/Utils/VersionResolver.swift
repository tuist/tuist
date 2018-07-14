import Basic
import Foundation
import Utility

protocol VersionResolving: AnyObject {
    func resolve(path: AbsolutePath) throws -> Version?
}

/// Version resolver errors.
///
/// - readError: thrown when a version file cannot be read.
/// - invalidFormat: thrown when the version file contains an invalid format.
enum VersionResolverError: FatalError {
    case readError(path: AbsolutePath)
    case invalidFormat(String, path: AbsolutePath)

    var errorDescription: String {
        switch self {
        case let .readError(path):
            return "Cannot read the version file at path \(path.asString)"
        case let .invalidFormat(value, path):
            return "The version \(value) at path \(path.asString) doesn't have a valid semver format (x.y.z)."
        }
    }
}

/// Resolves the version that should be used at the given path.
/// The tool looks up recursively the directory and its ancestors until it finds a .xpm-version
/// If a version is not defined it returns nil.
class VersionResolver: VersionResolving {
    /// Version file name.
    static let fileName = ".xpm-version"

    /// Resolves the version for the given path.
    ///
    /// - Parameter path: path for which the version will be resolved.
    /// - Returns: xpm version that should be used at the given path.
    func resolve(path: AbsolutePath) throws -> Version? {
        let filePath = path.appending(component: VersionResolver.fileName)
        if FileManager.default.fileExists(atPath: filePath.asString) {
            var value: String!
            do {
                value = try String(contentsOf: URL(fileURLWithPath: filePath.asString))
            } catch {
                throw VersionResolverError.readError(path: filePath)
            }
            guard let version = Version(string: value) else {
                throw VersionResolverError.invalidFormat(value, path: filePath)
            }
            return version
        } else if path.components.count > 1 {
            return try resolve(path: path.parentDirectory)
        }
        return nil
    }
}
