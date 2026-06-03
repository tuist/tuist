import Foundation
import Path
import TuistConstants
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

/// Computes, for a single target, the precompiled framework search paths and the consolidated
/// response file that `LinkGenerator` references from the build settings.
///
/// The computation is shared between `LinkGenerator` (which injects the build settings) and
/// `FrameworkSearchPathConsolidationGraphMapper` (which writes the response file) so the two can
/// never disagree about the threshold, the response file path, or its contents.
struct FrameworkSearchPathConsolidation {
    /// Targets with at least this many unique precompiled framework search paths get those paths
    /// consolidated into a response file to keep C/ObjC compilation and linking under ARG_MAX.
    static let threshold = 20

    let uniquePrecompiledPaths: [LinkGeneratorPath]
    let uniqueSdkPaths: [LinkGeneratorPath]
    let allUniquePaths: [LinkGeneratorPath]
    let precompiledXcodeValues: [String]
    let responseFilePath: AbsolutePath
    let responseFileReference: String
    let responseFileContents: String

    var isConsolidated: Bool {
        uniquePrecompiledPaths.count >= Self.threshold
    }

    static func compute(
        targetName: String,
        projectPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws -> FrameworkSearchPathConsolidation {
        let linkableModules = try graphTraverser.searchablePathDependencies(path: projectPath, name: targetName).sorted()

        let precompiledPaths = linkableModules.compactMap(\.precompiledPath)
            .map { LinkGeneratorPath.absolutePath($0.removingLastComponent()) }
        let sdkPaths = linkableModules.compactMap { (dependency: GraphDependencyReference) -> LinkGeneratorPath? in
            if case let GraphDependencyReference.sdk(_, _, source, _) = dependency {
                return source.frameworkSearchPath.map { LinkGeneratorPath.string($0) }
            } else {
                return nil
            }
        }

        let responseFilePath = sourceRootPath
            .appending(
                components: Constants.DerivedDirectory.name,
                Constants.DerivedDirectory.frameworkSearchPaths,
                "\(targetName).resp"
            )

        let precompiledXcodeValues = Array(Set(precompiledPaths))
            .map { $0.xcodeValue(sourceRootPath: sourceRootPath) }
            .uniqued()
            .sorted()

        // The response file must contain absolute paths since clang doesn't expand build setting
        // variables. Convert $(SRCROOT)/... to absolute paths.
        let responseFileContents = precompiledXcodeValues
            .map { "-F" + $0.replacingOccurrences(of: "$(SRCROOT)", with: sourceRootPath.pathString) }
            .joined(separator: "\n")
            + "\n"

        return FrameworkSearchPathConsolidation(
            uniquePrecompiledPaths: Array(Set(precompiledPaths)),
            uniqueSdkPaths: Array(Set(sdkPaths)),
            allUniquePaths: Array(Set(precompiledPaths + sdkPaths)),
            precompiledXcodeValues: precompiledXcodeValues,
            responseFilePath: responseFilePath,
            responseFileReference: "@$(SRCROOT)/\(responseFilePath.relative(to: sourceRootPath))",
            responseFileContents: responseFileContents
        )
    }
}

/// Writes the framework-search-path response files (`Derived/FrameworkSearchPaths/<Target>.resp`)
/// referenced by the consolidated `@file` build settings that `LinkGenerator` injects.
///
/// They are emitted here, as a graph-mapper side effect, rather than as a project side effect in
/// `LinkGenerator`, so they are written after `DeleteDerivedDirectoryProjectMapper` clears the
/// `Derived/` directory. Emitting them earlier meant a regeneration over an existing `Derived/`
/// deleted them, leaving the build referencing a missing `@file`. This mapper must run after the
/// binary-cache replacement mappers so it sees the precompiled xcframework dependencies.
public struct FrameworkSearchPathConsolidationGraphMapper: GraphMapping {
    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        Logger.current.debug("Transforming graph \(graph.name): Writing framework search path response files")

        let graphTraverser = GraphTraverser(graph: graph)
        var sideEffects: [SideEffectDescriptor] = []

        for project in graph.projects.values {
            for target in project.targets.values {
                let consolidation = try FrameworkSearchPathConsolidation.compute(
                    targetName: target.name,
                    projectPath: project.path,
                    sourceRootPath: project.sourceRootPath,
                    graphTraverser: graphTraverser
                )
                guard consolidation.isConsolidated else { continue }
                sideEffects.append(
                    .file(FileDescriptor(
                        path: consolidation.responseFilePath,
                        contents: Data(consolidation.responseFileContents.utf8)
                    ))
                )
            }
        }

        return (graph, sideEffects, environment)
    }
}
