import Basic
import Foundation
import TuistSupport

enum XCFrameworkMetadataProviderError: FatalError, Equatable {
    
    case missingRequiredFile(AbsolutePath)
    case supportedArchitectureReferencesNotFound(AbsolutePath)
    
    
    // MARK: - FatalError
    
    var description: String {
        switch self {
        case let .missingRequiredFile(path):
            return "The .xcframework at path \(path.pathString) doesn't contain an Info.plist. It's possible that the .xcframework was not generated properly or that got corrupted. Please, double check with the author of the framework."
        case let .supportedArchitectureReferencesNotFound(path):
            return "Couldn't find supported architecture references at \(path.pathString). It's possible that the .xcframework was not generated properly or that got corrupted. Please, double check with the author of the framework."
        }
    }
    
    var type: ErrorType {
        switch self {
        case .missingRequiredFile, .supportedArchitectureReferencesNotFound:
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
            let infoPlist = frameworkPath.appending(component: "Info.plist")
            throw XCFrameworkMetadataProviderError.supportedArchitectureReferencesNotFound(infoPlist)
        }
        let binaryName = frameworkPath.basenameWithoutExt
        let binaryPath =  AbsolutePath(library.identifier, relativeTo: frameworkPath)
            .appending(RelativePath(library.path.pathString))
            .appending(component: binaryName)
        
        return binaryPath
    }
}
