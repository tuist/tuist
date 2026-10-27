import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol defining how to map a single `PBXTargetDependency` into a `TargetDependency` model.
///
/// Conforming types handle all known dependency types—direct targets, package products,
/// proxy references (which may point to other targets or external projects), and file-based dependencies.
protocol PBXTargetDependencyMapping {
    /// Maps a single `PBXTargetDependency` into a `TargetDependency` model.
    ///
    /// - Parameters:
    ///   - dependency: The `PBXTargetDependency` to map.
    ///   - xcodeProj: Provides the `.xcodeproj` data and source directory paths.
    /// - Returns: A `TargetDependency` if the dependency can be resolved.
    /// - Throws: If the dependency references invalid paths or targets that cannot be resolved.
    func map(_ dependency: PBXTargetDependency, xcodeProj: XcodeProj) throws -> TargetDependency
}

/// A unified mapper that handles all types of `PBXTargetDependency` instances.
///
/// `PBXTargetDependencyMapper` checks if the dependency references a direct target, a package product,
/// or a proxy. For proxy dependencies, it may resolve references to another target, a project,
/// or file-based dependencies (frameworks, libraries, etc.). If a dependency cannot be resolved
/// to a known domain model, it throws an error.
struct PBXTargetDependencyMapper: PBXTargetDependencyMapping {
    private let pathMapper: PathDependencyMapping

    init(pathMapper: PathDependencyMapping = PathDependencyMapper()) {
        self.pathMapper = pathMapper
    }

    func map(_ dependency: PBXTargetDependency, xcodeProj: XcodeProj) throws -> TargetDependency {
        let condition = dependency.platformCondition()

        // 1. Direct target dependency
        if let target = dependency.target {
            return .target(name: target.name, status: .required, condition: condition)
        }

        // 2. Package product dependency
        if let product = dependency.product {
            return .package(
                product: product.productName,
                type: .runtime,
                condition: condition
            )
        }

        // 3. Proxy dependency
        if let targetProxy = dependency.targetProxy {
            switch targetProxy.proxyType {
            case .nativeTarget:
                return try mapNativeTargetProxy(targetProxy, condition: condition, xcodeProj: xcodeProj)
            case .reference:
                return try mapReferenceProxy(targetProxy, condition: condition, xcodeProj: xcodeProj)
            case .other, .none:
                throw TargetDependencyMappingError.unsupportedProxyType(dependency.name)
            }
        }

        // If none of the above matched, it's an unknown dependency type.
        throw TargetDependencyMappingError.unknownDependencyType(
            name: dependency.name ?? "Unknown dependency name"
        )
    }

    // MARK: - Private Helpers

    private func mapNativeTargetProxy(
        _ targetProxy: PBXContainerItemProxy,
        condition: PlatformCondition?,
        xcodeProj: XcodeProj
    ) throws -> TargetDependency {
        let remoteInfo = try targetProxy.remoteInfo.throwing(
            TargetDependencyMappingError.missingRemoteInfoInNativeProxy
        )

        switch targetProxy.containerPortal {
        case .project:
            // Direct reference to another target in the same project.
            return .target(name: remoteInfo, status: .required, condition: condition)
        case let .fileReference(fileReference):
            let projectRelativePath = try fileReference.path
                .throwing(TargetDependencyMappingError.missingFileReference(fileReference.name ?? ""))

            let path = xcodeProj.srcPath.appending(component: projectRelativePath)
            // Reference to a target in another project.
            return .project(target: remoteInfo, path: path, status: .required, condition: condition)
        case let .unknownObject(object):
            throw TargetDependencyMappingError.unknownObject(object.debugDescription)
        }
    }

    private func mapReferenceProxy(
        _ targetProxy: PBXContainerItemProxy,
        condition: PlatformCondition?,
        xcodeProj: XcodeProj
    ) throws -> TargetDependency {
        let remoteGlobalID = try targetProxy.remoteGlobalID.throwing(
            TargetDependencyMappingError.missingRemoteGlobalIDInReferenceProxy
        )

        switch remoteGlobalID {
        case let .object(object):
            // File-based dependency
            if let fileRef = object as? PBXFileReference {
                return try mapFileDependency(
                    pathString: fileRef.path,
                    expectedSignature: nil,
                    condition: condition,
                    xcodeProj: xcodeProj
                )
            } else if let refProxy = object as? PBXReferenceProxy {
                return try mapFileDependency(
                    pathString: refProxy.path,
                    expectedSignature: nil,
                    condition: condition,
                    xcodeProj: xcodeProj
                )
            }
            throw TargetDependencyMappingError.unknownObject("\(object)")

        case .string:
            // If remoteGlobalID is just a string, we can’t map a file or target from it.
            throw TargetDependencyMappingError.unknownDependencyType(
                name: "remoteGlobalID is a string, cannot map a known target or file reference."
            )
        }
    }

    /// Maps file-based dependencies (e.g., frameworks, libraries) into `TargetDependency` models.
    /// - Parameters:
    ///   - pathString: The path string for the file-based dependency (relative or absolute).
    ///   - expectedSignature: The expected signature if `path` is of a signed XCFramework, `nil` otherwise.
    ///   - condition: An optional platform condition.
    ///   - xcodeProj: The Xcode project reference for resolving the directory structure.
    /// - Returns: A `TargetDependency` reflecting the file’s extension (framework, library, etc.).
    /// - Throws: If the path is missing or invalid.
    private func mapFileDependency(
        pathString: String?,
        expectedSignature: XCFrameworkSignature?,
        condition: PlatformCondition?,
        xcodeProj: XcodeProj
    ) throws -> TargetDependency {
        let pathString = try pathString.throwing(
            TargetDependencyMappingError.missingFileReference("Path string is nil in file dependency.")
        )
        let path = xcodeProj.srcPath.appending(try RelativePath(validating: pathString))
        return try pathMapper.map(path: path, expectedSignature: expectedSignature, condition: condition)
    }
}

// MARK: - Errors

/// Errors that may occur when mapping `PBXTargetDependency` instances.
enum TargetDependencyMappingError: LocalizedError, Equatable {
    case targetNotFound(targetName: String, path: AbsolutePath)
    case unknownDependencyType(name: String)
    case missingFileReference(String)
    case unknownObject(String)
    case missingRemoteInfoInNativeProxy
    case missingRemoteGlobalIDInReferenceProxy
    case unsupportedProxyType(String?)

    var errorDescription: String? {
        switch self {
        case let .targetNotFound(targetName, path):
            return "The target '\(targetName)' could not be found in the project at: \(path.pathString)."
        case let .unknownDependencyType(name):
            return "An unknown dependency type '\(name)' was encountered."
        case let .missingFileReference(description):
            return "File reference path is missing in target dependency: \(description)."
        case let .unknownObject(description):
            return "Encountered an unknown PBXObject in target dependency: \(description)."
        case .missingRemoteInfoInNativeProxy:
            return "A native target proxy is missing `remoteInfo` in target dependency."
        case .missingRemoteGlobalIDInReferenceProxy:
            return "A reference proxy is missing `remoteGlobalID` in target dependency."
        case let .unsupportedProxyType(name):
            return "Encountered an unsupported PBXProxyType in dependency: \(name ?? "Unknown")."
        }
    }
}
