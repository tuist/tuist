import Foundation
import Path
import TuistConstants
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

/// Owns the framework-search-path setup for every target: it derives the precompiled and SDK
/// framework search paths from the target's dependency graph and writes the corresponding build
/// settings onto the target, plus — for targets above the consolidation threshold — the
/// `Derived/FrameworkSearchPaths/<Target>.resp` response file.
///
/// This used to live in `LinkGenerator` (a project-descriptor generator), but the response file was
/// emitted there as a *project* side effect, which runs before the mapper side effects. So on a
/// regeneration over an existing `Derived/`, `DeleteDerivedDirectoryProjectMapper`'s cleanup (a
/// mapper side effect) deleted the just-written file, leaving the build referencing a missing
/// `@file`. Owning the whole thing in a graph mapper means the file is written in the same
/// side-effect batch as the cleanup, after the deletes, so it survives — consistent with how
/// `ModuleMapMapper` writes the deps module maps. It is registered after the binary-cache
/// replacement mappers so it sees the precompiled xcframework dependencies.
public struct FrameworkSearchPathsGraphMapper: GraphMapping {
    private static let frameworkSearchPathsSetting = "FRAMEWORK_SEARCH_PATHS"
    private static let otherCFlagsSetting = "OTHER_CFLAGS"
    private static let otherSwiftFlagsSetting = "OTHER_SWIFT_FLAGS"
    private static let otherLinkerFlagsSetting = "OTHER_LDFLAGS"

    private struct TargetID: Hashable {
        let projectPath: AbsolutePath
        let targetName: String
    }

    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        Logger.current.debug("Transforming graph \(graph.name): Setting up framework search paths")

        let graphTraverser = GraphTraverser(graph: graph)

        var consolidations: [TargetID: FrameworkSearchPathConsolidation] = [:]
        for (_, project) in graph.projects {
            for (_, target) in project.targets {
                consolidations[TargetID(projectPath: project.path, targetName: target.name)] =
                    try FrameworkSearchPathConsolidation.compute(
                        targetName: target.name,
                        projectPath: project.path,
                        sourceRootPath: project.sourceRootPath,
                        graphTraverser: graphTraverser
                    )
            }
        }

        var graph = graph
        var sideEffects: [SideEffectDescriptor] = []

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { targetName, target in
                guard let consolidation = consolidations[TargetID(projectPath: project.path, targetName: target.name)],
                      !consolidation.isEmpty
                else { return (targetName, target) }
                var target = target
                target.settings = apply(consolidation, to: target.settings, defaultSettings: project.settings.defaultSettings)
                return (target.name, target)
            })
            return (projectPath, project)
        })

        for consolidation in consolidations.values where consolidation.isConsolidated {
            sideEffects.append(
                .file(FileDescriptor(
                    path: consolidation.responseFilePath,
                    contents: Data(consolidation.responseFileContents.utf8)
                ))
            )
        }

        return (graph, sideEffects, environment)
    }

    /// Applies the consolidation's build settings to the target's base settings and to any
    /// configuration that already overrides one of the affected keys. Configuration-level keys
    /// shadow the base value entirely, so patching only the base would drop the flags for targets
    /// that override e.g. `OTHER_SWIFT_FLAGS` per configuration (mirrors `ModuleMapMapper`).
    private func apply(
        _ consolidation: FrameworkSearchPathConsolidation,
        to settings: Settings?,
        defaultSettings: DefaultSettings
    ) -> Settings {
        let settings = settings ?? Settings(base: [:], configurations: [:], defaultSettings: defaultSettings)
        return Settings(
            base: applied(consolidation, to: settings.base),
            baseDebug: settings.baseDebug,
            configurations: settings.configurations.mapValues { configuration in
                guard let configuration else { return nil }
                return configuration.with(settings: applied(consolidation, to: configuration.settings, onlyExistingKeys: true))
            },
            defaultSettings: settings.defaultSettings,
            defaultConfiguration: settings.defaultConfiguration
        )
    }

    private func applied(
        _ consolidation: FrameworkSearchPathConsolidation,
        to settings: SettingsDictionary,
        onlyExistingKeys: Bool = false
    ) -> SettingsDictionary {
        var settings = settings
        var additions: [(key: String, values: [String])] = [
            (Self.frameworkSearchPathsSetting, consolidation.frameworkSearchPathValues),
        ]
        if consolidation.isConsolidated {
            additions.append((Self.otherCFlagsSetting, [consolidation.responseFileReference]))
            additions.append((Self.otherSwiftFlagsSetting, consolidation.swiftFrameworkSearchPathFlags))
            additions.append((Self.otherLinkerFlagsSetting, [consolidation.responseFileReference]))
        }
        for (key, values) in additions where !values.isEmpty {
            if onlyExistingKeys, settings[key] == nil { continue }
            settings[key] = extended(settings[key], with: values)
        }
        return settings
    }

    private func extended(_ value: SettingsDictionary.Value?, with values: [String]) -> SettingsDictionary.Value {
        var current: [String]
        switch value ?? .array(["$(inherited)"]) {
        case let .array(existing):
            current = existing
        case let .string(string):
            current = string.split(separator: " ").map(String.init)
        }
        current.append(contentsOf: values)
        return .array(current)
    }
}

/// Computes, for a single target, the precompiled framework search paths and the consolidated
/// response file. Used only by `FrameworkSearchPathsGraphMapper`; extracted so the values can be
/// unit-tested with a mocked graph traverser.
struct FrameworkSearchPathConsolidation {
    /// Targets with at least this many unique precompiled framework search paths get those paths
    /// consolidated into a response file to keep C/ObjC compilation and linking under ARG_MAX.
    static let threshold = 20

    private let uniquePrecompiledPaths: [LinkGeneratorPath]
    private let uniqueSdkPaths: [LinkGeneratorPath]
    private let allUniquePaths: [LinkGeneratorPath]
    private let sourceRootPath: AbsolutePath
    private let precompiledXcodeValues: [String]

    let responseFilePath: AbsolutePath
    let responseFileReference: String
    let responseFileContents: String

    var isConsolidated: Bool {
        uniquePrecompiledPaths.count >= Self.threshold
    }

    /// Whether there is anything to set at all (no precompiled and no SDK framework search paths).
    var isEmpty: Bool {
        allUniquePaths.isEmpty
    }

    /// The `FRAMEWORK_SEARCH_PATHS` values: SDK-only when consolidated (the precompiled paths move
    /// to the response file), otherwise the full set.
    var frameworkSearchPathValues: [String] {
        let paths = isConsolidated ? uniqueSdkPaths : allUniquePaths
        return paths.map { $0.xcodeValue(sourceRootPath: sourceRootPath) }.uniqued().sorted()
    }

    /// The inline `-F` flags for `OTHER_SWIFT_FLAGS` (Swift has no ARG_MAX problem and routing it
    /// through `@file` is broken under Xcode 26).
    var swiftFrameworkSearchPathFlags: [String] {
        precompiledXcodeValues.flatMap { ["-F", $0] }
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
            sourceRootPath: sourceRootPath,
            precompiledXcodeValues: precompiledXcodeValues,
            responseFilePath: responseFilePath,
            responseFileReference: "@$(SRCROOT)/\(responseFilePath.relative(to: sourceRootPath))",
            responseFileContents: responseFileContents
        )
    }
}
