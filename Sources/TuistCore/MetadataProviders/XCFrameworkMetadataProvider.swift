import Foundation
import TSCBasic
import TuistSupport

enum XCFrameworkMetadataProviderError: FatalError, Equatable {
    case missingRequiredFile(AbsolutePath)
    case supportedArchitectureReferencesNotFound(AbsolutePath)
    case fileTypeNotRecognised(file: RelativePath, frameworkName: String)

    // MARK: - FatalError

    var description: String {
        switch self {
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
        case .missingRequiredFile, .supportedArchitectureReferencesNotFound, .fileTypeNotRecognised:
            return .abort
        }
    }
}

protocol XCFrameworkMetadataProviding: PrecompiledMetadataProviding {
    /// Returns the info.plist of the xcframework at the given path.
    /// - Parameter xcframeworkPath: Path to the xcframework.
    func infoPlist(xcframeworkPath: AbsolutePath) throws -> XCFrameworkInfoPlist

    /// Given a framework path and libraries it returns the path to its binary.
    /// - Parameter xcframeworkPath: Path to the .xcframework
    /// - Parameter libraries: Framework available libraries
    func binaryPath(xcframeworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath
}

class XCFrameworkMetadataProvider: PrecompiledMetadataProvider, XCFrameworkMetadataProviding {
    func infoPlist(xcframeworkPath: AbsolutePath) throws -> XCFrameworkInfoPlist {
        let fileHandler = FileHandler.shared
        let infoPlist = xcframeworkPath.appending(component: "Info.plist")
        guard fileHandler.exists(infoPlist) else {
            throw XCFrameworkMetadataProviderError.missingRequiredFile(infoPlist)
        }

        return try fileHandler.readPlistFile(infoPlist)
    }

    func binaryPath(xcframeworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath {
        let archs: [BinaryArchitecture] = [.arm64, .x8664]
        guard let library = libraries.first(where: { !$0.architectures.filter(archs.contains).isEmpty }) else {
            throw XCFrameworkMetadataProviderError.supportedArchitectureReferencesNotFound(xcframeworkPath)
        }
        let binaryName = xcframeworkPath.basenameWithoutExt

        let binaryPath: AbsolutePath

        switch library.path.extension {
        case "framework":
            binaryPath = AbsolutePath(library.identifier, relativeTo: xcframeworkPath)
                .appending(RelativePath(library.path.pathString))
                .appending(component: binaryName)
        case "a":
            binaryPath = AbsolutePath(library.identifier, relativeTo: xcframeworkPath)
                .appending(RelativePath(library.path.pathString))
        default:
            throw XCFrameworkMetadataProviderError.fileTypeNotRecognised(file: library.path, frameworkName: xcframeworkPath.basename)
        }
        return binaryPath
    }
}
