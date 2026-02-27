import Foundation
import Path
import XcodeGraph

/// A protocol defining how to map a file path into a `TargetDependency` based on its extension.
protocol PathDependencyMapping {
    /// Maps the given path to a `TargetDependency`.
    ///
    /// - Parameters:
    ///   - path: The file path to map.
    ///   - expectedSignature: The expected signature if `path` is of a signed XCFramework, `nil` otherwise.
    ///   - condition: An optional platform condition (e.g., iOS only).
    /// - Returns: The corresponding `TargetDependency`, if the path extension is recognized.
    /// - Throws: `PathDependencyError.invalidExtension` if the file extension is not supported.
    func map(path: AbsolutePath, expectedSignature: XCFrameworkSignature?, condition: PlatformCondition?) throws
        -> TargetDependency
}

/// A mapper that converts file paths (like `.framework`, `.xcframework`, or libraries) to `TargetDependency` models.
struct PathDependencyMapper: PathDependencyMapping {
    func map(
        path: AbsolutePath,
        expectedSignature: XCFrameworkSignature? = nil,
        condition: PlatformCondition?
    ) throws -> TargetDependency {
        let status: LinkingStatus = .required

        switch path.fileExtension {
        case .framework:
            return .framework(path: path, status: status, condition: condition)
        case .xcframework:
            return .xcframework(
                path: path,
                expectedSignature: expectedSignature ?? .unsigned,
                status: status,
                condition: condition
            )
        case .dynamicLibrary, .textBasedDynamicLibrary, .staticLibrary:
            return .library(
                path: path,
                publicHeaders: path.parentDirectory, // heuristics; can be overridden if needed
                swiftModuleMap: nil,
                condition: condition
            )
        case .xcodeproj, .xcworkspace, .coreData, .playground, .none:
            throw PathDependencyError.invalidExtension(path: path.pathString)
        }
    }
}

/// Errors that may occur when mapping paths to `TargetDependency`.
enum PathDependencyError: Error, LocalizedError {
    case invalidExtension(path: String)

    var errorDescription: String? {
        switch self {
        case let .invalidExtension(path):
            return "Encountered an invalid or unsupported file extension: \(path)"
        }
    }
}

/// Common file extensions encountered in Xcode projects and their associated artifacts.
enum FileExtension: String {
    case xcodeproj
    case xcworkspace
    case framework
    case xcframework
    case staticLibrary = "a"
    case dynamicLibrary = "dylib"
    case textBasedDynamicLibrary = "tbd"
    case coreData = "xcdatamodeld"
    case playground
}

/// A convenience extension to retrieve a file's `FileExtension` from `AbsolutePath`.
extension AbsolutePath {
    var fileExtension: FileExtension? {
        guard let ext = `extension`?.lowercased() else { return nil }
        return FileExtension(rawValue: ext)
    }
}
