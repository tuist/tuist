import Basic
import Foundation
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

public protocol XCFrameworkMetadataProviding {
    /// Returns the available libraries for the xcframework at the given path.
    /// - Parameter frameworkPath: Path to the xcframework.
    func libraries(frameworkPath: AbsolutePath) throws -> [XCFrameworkInfoPlist.Library]

    /// Given a framework path and libraries it returns the path to its binary.
    /// - Parameter frameworkPath: Framework path.
    /// - Parameter libraries: Framework available libraries
    func binaryPath(frameworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath
}

public class XCFrameworkMetadataProvider: XCFrameworkMetadataProviding {
    public func libraries(frameworkPath: AbsolutePath) throws -> [XCFrameworkInfoPlist.Library] {
        let fileHandler = FileHandler.shared
        let infoPlist = frameworkPath.appending(component: "Info.plist")
        guard fileHandler.exists(infoPlist) else {
            throw XCFrameworkMetadataProviderError.missingRequiredFile(infoPlist)
        }

        let config: XCFrameworkInfoPlist = try fileHandler.readPlistFile(infoPlist)
        return config.libraries
    }

    public func binaryPath(frameworkPath: AbsolutePath, libraries: [XCFrameworkInfoPlist.Library]) throws -> AbsolutePath {
        let archs: [BinaryArchitecture] = [.arm64, .x8664]
        guard let library = libraries.first(where: { !$0.architectures.filter(archs.contains).isEmpty }) else {
            throw XCFrameworkMetadataProviderError.supportedArchitectureReferencesNotFound(frameworkPath)
        }
        let binaryName = frameworkPath.basenameWithoutExt
        
        let binaryPath: AbsolutePath
        
        switch library.path.extension {
        case "framework":
            binaryPath = AbsolutePath(library.identifier, relativeTo: frameworkPath)
                .appending(RelativePath(library.path.pathString))
                .appending(component: binaryName)
        case "a":
            binaryPath = AbsolutePath(library.identifier, relativeTo: frameworkPath)
                .appending(RelativePath(library.path.pathString))
        default:
            throw XCFrameworkMetadataProviderError.fileTypeNotRecognised(file: library.path, frameworkName: frameworkPath.basename)
        }
        return binaryPath
    }
}
