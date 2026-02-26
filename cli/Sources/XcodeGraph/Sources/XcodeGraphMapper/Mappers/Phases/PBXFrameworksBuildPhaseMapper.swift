import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol for mapping a `PBXFrameworksBuildPhase` into associated `TargetDependency`s.
protocol PBXFrameworksBuildPhaseMapping {
    /// Maps the given frameworks build phase to a list of `TargetDependency` instances.
    ///
    /// - Parameters:
    ///   - frameworksBuildPhase: The `PBXFrameworksBuildPhase` to map.
    ///   - xcodeProj: The `XcodeProj` for path resolution.
    /// - Returns: An array of `TargetDependency` objects representing the frameworks.
    /// - Throws: If any file paths or references cannot be resolved.
    func map(
        _ frameworksBuildPhase: PBXFrameworksBuildPhase,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) throws -> [TargetDependency]
}

/// The default mapper that converts `PBXFrameworksBuildPhase` files into `TargetDependency` models.
struct PBXFrameworksBuildPhaseMapper: PBXFrameworksBuildPhaseMapping {
    private let pathMapper: PathDependencyMapping

    init(pathMapper: PathDependencyMapping = PathDependencyMapper()) {
        self.pathMapper = pathMapper
    }

    func map(
        _ frameworksBuildPhase: PBXFrameworksBuildPhase,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) throws -> [TargetDependency] {
        let files = frameworksBuildPhase.files ?? []
        return try files.map {
            try mapFrameworkDependency(
                $0,
                xcodeProj: xcodeProj,
                projectNativeTargets: projectNativeTargets
            )
        }
    }

    // MARK: - Private Helpers

    /// Maps a single PBXBuildFile from the frameworks build phase to a `TargetDependency`.
    private func mapFrameworkDependency(
        _ buildFile: PBXBuildFile,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) throws -> TargetDependency {
        if let product = buildFile.product {
            return .package(
                product: product.productName,
                type: .runtime,
                condition: nil
            )
        }
        let fileRef = try buildFile.file.throwing(
            PBXFrameworksBuildPhaseMappingError.missingFileReference(
                buildFile.uuid,
                xcodeProj.projectPath.appending(component: "project.pbxproj")
            )
        )
        if let path = fileRef.path {
            let name = path.replacingOccurrences(of: ".framework", with: "")
            let linkingStatus: LinkingStatus = buildFile.attributes?
                .contains("Weak") == true ? .optional : .required
            switch fileRef.sourceTree {
            case .buildProductsDir:
                if let target = xcodeProj.pbxproj.targets(named: name).first {
                    return .target(
                        name: target.name,
                        status: linkingStatus,
                        condition: nil
                    )
                } else if let projectNativeTarget = projectNativeTargets[name] {
                    return .project(
                        target: projectNativeTarget.nativeTarget.name,
                        path: projectNativeTarget.project.projectPath.parentDirectory,
                        status: linkingStatus,
                        condition: nil
                    )
                }
            case .sdkRoot, .developerDir:
                return .sdk(
                    name: name,
                    status: linkingStatus,
                    condition: nil
                )
            default:
                break
            }
        }
        let filePathString = try fileRef.fullPath(sourceRoot: xcodeProj.srcPathString)
            .throwing(PBXFrameworksBuildPhaseMappingError.missingFilePath(name: fileRef.name))

        let absolutePath = try AbsolutePath(validating: filePathString)
        return try pathMapper.map(path: absolutePath, expectedSignature: nil, condition: nil)
    }
}

/// Errors that may occur when mapping framework build phase files.
enum PBXFrameworksBuildPhaseMappingError: Error, LocalizedError {
    case missingFileReference(String, AbsolutePath)
    case missingFilePath(name: String?)

    var errorDescription: String? {
        switch self {
        case let .missingFileReference(buildFileUUID, pbxprojPath):
            return "Missing 'PBXBuildFile.file' reference for \(buildFileUUID) id. Make sure an element with that id is present in the \(pbxprojPath.pathString) file."
        case let .missingFilePath(name):
            let fileName = name ?? "Unknown"
            return "Missing or invalid file path for 'PBXBuildFile': \(fileName)."
        }
    }
}
