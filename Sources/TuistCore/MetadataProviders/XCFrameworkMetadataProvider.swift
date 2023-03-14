import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

// MARK: - Provider Errors

enum XCFrameworkMetadataProviderError: FatalError, Equatable {
    case xcframeworkNotFound(AbsolutePath)
    case missingRequiredFile(AbsolutePath)
    case supportedArchitectureReferencesNotFound(AbsolutePath)
    case fileTypeNotRecognised(file: RelativePath, frameworkName: String)

    // MARK: - FatalError

    var description: String {
        switch self {
        case let .xcframeworkNotFound(path):
            return "Couldn't find xcframework at \(path.pathString)"
        case let .missingRequiredFile(path):
            return "The .xcframework at path \(path.pathString) doesn't contain an Info.plist. It's possible that the .xcframework was not generated properly or that got corrupted. Please, double check with the author of the framework."
        case let .supportedArchitectureReferencesNotFound(path):
            return "Couldn't find any supported architecture references at \(path.pathString). It's possible that the .xcframework was not generated properly or that it got corrupted. Please, double check with the author of the framework."
        case let .fileTypeNotRecognised(file, frameworkName):
            return "The extension of the file `\(file)`, which was found while parsing the xcframework `\(frameworkName)`, is not supported."
        }
    }

    var type: ErrorType {
        switch self {
        case .xcframeworkNotFound, .missingRequiredFile, .supportedArchitectureReferencesNotFound, .fileTypeNotRecognised:
            return .abort
        }
    }
}

// MARK: - Provider

public protocol XCFrameworkMetadataProviding: PrecompiledMetadataProviding {
    /// Loads all the metadata associated with an XCFramework at the specified path
    /// - Note: This performs various shell calls and disk operations
    func loadMetadata(at path: AbsolutePath) throws -> XCFrameworkMetadata

    /// Returns the info.plist of the xcframework at the given path.
    /// - Parameter xcframeworkPath: Path to the xcframework.
    func infoPlist(xcframeworkPath: AbsolutePath) throws -> XCFrameworkInfoPlist

    /// Given a framework path and libraries it returns the path to its binary.
    /// - Parameter xcframeworkPath: Path to the .xcframework
    /// - Parameter libraries: Framework available libraries
    func binaryPath(xcframeworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath
}

// MARK: - Default Implementation

public final class XCFrameworkMetadataProvider: PrecompiledMetadataProvider, XCFrameworkMetadataProviding {
    override public init() {
        super.init()
    }

    public func loadMetadata(at path: AbsolutePath) throws -> XCFrameworkMetadata {
        let fileHandler = FileHandler.shared
        guard fileHandler.exists(path) else {
            throw XCFrameworkMetadataProviderError.xcframeworkNotFound(path)
        }
        let infoPlist = try infoPlist(xcframeworkPath: path)
        let primaryBinaryPath = try binaryPath(
            xcframeworkPath: path,
            libraries: infoPlist.libraries
        )
        let linking = try linking(binaryPath: primaryBinaryPath)
        return XCFrameworkMetadata(
            path: path,
            infoPlist: infoPlist,
            primaryBinaryPath: primaryBinaryPath,
            linking: linking
        )
    }

    public func infoPlist(xcframeworkPath: AbsolutePath) throws -> XCFrameworkInfoPlist {
        let fileHandler = FileHandler.shared
        let infoPlist = xcframeworkPath.appending(component: "Info.plist")
        guard fileHandler.exists(infoPlist) else {
            throw XCFrameworkMetadataProviderError.missingRequiredFile(infoPlist)
        }

        return try fileHandler.readPlistFile(infoPlist)
    }

    public func binaryPath(xcframeworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath {
        let archs: [BinaryArchitecture] = [.arm64, .x8664]

        guard let library = libraries.first(where: {
            let hasValidArchitectures = !$0.architectures.filter(archs.contains).isEmpty
            guard hasValidArchitectures, let binaryPath = try? path(
                for: $0,
                xcframeworkPath: xcframeworkPath
            ) else {
                return false
            }
            guard FileHandler.shared.exists(binaryPath) else {
                // The missing slice relative to the XCFramework folder. e.g ios-x86_64-simulator/Alamofire.framework/Alamofire
                let relativeArchitectureBinaryPath = binaryPath.components.suffix(3).joined(separator: "/")
                logger
                    .warning(
                        "\(xcframeworkPath.basename) is missing architecture \(relativeArchitectureBinaryPath) defined in the Info.plist"
                    )
                return false
            }
            return true
        }) else {
            throw XCFrameworkMetadataProviderError.supportedArchitectureReferencesNotFound(xcframeworkPath)
        }

        return try path(for: library, xcframeworkPath: xcframeworkPath)
    }

    private func path(
        for library: XCFrameworkInfoPlist.Library,
        xcframeworkPath: AbsolutePath
    ) throws -> AbsolutePath {
        let binaryPath: AbsolutePath

        switch library.path.extension {
        case "framework":
            binaryPath = try AbsolutePath(validating: library.identifier, relativeTo: xcframeworkPath)
                .appending(RelativePath(library.path.pathString))
                .appending(component: library.path.basenameWithoutExt)
        case "a":
            binaryPath = try AbsolutePath(validating: library.identifier, relativeTo: xcframeworkPath)
                .appending(RelativePath(library.path.pathString))
        default:
            throw XCFrameworkMetadataProviderError.fileTypeNotRecognised(
                file: library.path,
                frameworkName: xcframeworkPath.basename
            )
        }
        return binaryPath
    }
}
