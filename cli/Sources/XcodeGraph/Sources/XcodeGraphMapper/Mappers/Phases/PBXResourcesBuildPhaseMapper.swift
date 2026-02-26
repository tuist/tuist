import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol for mapping a PBXResourcesBuildPhase into an array of ResourceFileElement.
protocol PBXResourcesBuildPhaseMapping {
    /// Converts the given resources build phase to a list of `ResourceFileElement` models.
    /// - Parameters:
    ///   - resourcesBuildPhase: The build phase that may contain resource files and variant groups.
    ///   - xcodeProj: The `XcodeProj` used for path resolution.
    /// - Returns: An array of `ResourceFileElement`s, representing file paths or grouped variants.
    /// - Throws: If any file references are missing or paths cannot be resolved.
    func map(
        _ resourcesBuildPhase: PBXResourcesBuildPhase,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) throws -> (resources: [ResourceFileElement], resourceDependencies: [TargetDependency])
}

/// A mapper that converts a `PBXResourcesBuildPhase` into a list of `ResourceFileElement`.
struct PBXResourcesBuildPhaseMapper: PBXResourcesBuildPhaseMapping {
    func map(
        _ resourcesBuildPhase: PBXResourcesBuildPhase,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) throws -> (resources: [ResourceFileElement], resourceDependencies: [TargetDependency]) {
        let files = resourcesBuildPhase.files ?? []
        let (resources, resourceDependencies): ([ResourceFileElement], [TargetDependency]) = try files.reduce((
            [],
            []
        )) { acc, buildFile in
            let result = try mapResourceElement(buildFile, xcodeProj: xcodeProj, projectNativeTargets: projectNativeTargets)
            return (acc.0 + result.0, acc.1 + result.1)
        }

        return (
            resources.sorted(by: { $0.path < $1.path }),
            resourceDependencies.sorted(by: { $0.name < $1.name })
        )
    }

    // MARK: - Private Helpers

    /// Maps a single `PBXBuildFile` to one or more `ResourceFileElement`s.
    private func mapResourceElement(
        _ buildFile: PBXBuildFile,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) throws -> ([ResourceFileElement], [TargetDependency]) {
        let fileElement = try buildFile.file
            .throwing(PBXResourcesMappingError.missingFileReference)

        // If it's a PBXVariantGroup, map each child within that group.
        if let variantGroup = fileElement as? PBXVariantGroup {
            return try mapVariantGroup(variantGroup, xcodeProj: xcodeProj, projectNativeTargets: projectNativeTargets)
        } else {
            // Otherwise, it's a straightforward file or reference.
            return try mapFileElement(
                fileElement,
                xcodeProj: xcodeProj,
                projectNativeTargets: projectNativeTargets
            )
        }
    }

    /// Maps a simple (non-variant) file element to a list (usually a single entry) of `ResourceFileElement`.
    private func mapFileElement(
        _ fileElement: PBXFileElement,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) throws -> ([ResourceFileElement], [TargetDependency]) {
        switch fileElement.sourceTree {
        case .buildProductsDir:
            guard let path = fileElement.path else { break }
            let name = path.replacingOccurrences(of: ".bundle", with: "")
            if let target = xcodeProj.pbxproj.targets(named: name).first {
                return (
                    [],
                    [
                        .target(
                            name: target.name,
                            status: .required,
                            condition: nil
                        ),
                    ]
                )
            } else if let projectNativeTarget = projectNativeTargets[name] {
                return (
                    [],
                    [
                        .project(
                            target: projectNativeTarget.nativeTarget.name,
                            path: projectNativeTarget.project.projectPath.parentDirectory,
                            status: .required,
                            condition: nil
                        ),
                    ]
                )
            }
        default:
            break
        }

        let pathString = try fileElement
            .fullPath(sourceRoot: xcodeProj.srcPathString)
            .throwing(PBXResourcesMappingError.missingFullPath(fileElement.name ?? "Unknown"))
        let absolutePath = try AbsolutePath(validating: pathString)
        return ([.file(path: absolutePath)], [])
    }

    /// Maps a PBXVariantGroup by expanding each child into a `ResourceFileElement`.
    private func mapVariantGroup(
        _ variantGroup: PBXVariantGroup,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) throws -> ([ResourceFileElement], [TargetDependency]) {
        try variantGroup.children.reduce(([], [])) { acc, child in
            let result = try mapFileElement(
                child,
                xcodeProj: xcodeProj,
                projectNativeTargets: projectNativeTargets
            )
            return (acc.0 + result.0, acc.1 + result.1)
        }
    }
}

/// Example error types for resource mapping.
enum PBXResourcesMappingError: LocalizedError {
    case missingFileReference
    case missingFullPath(String)

    var errorDescription: String? {
        switch self {
        case .missingFileReference:
            return "Missing file reference for resource."
        case let .missingFullPath(name):
            return "No valid path for resource file element: \(name)."
        }
    }
}
