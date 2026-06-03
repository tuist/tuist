import Foundation
import Path
import TuistConstants
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

/// Sets up framework search paths for every target: it derives the precompiled and SDK framework
/// search paths from the target's dependency graph, writes the corresponding build settings onto
/// the target, and — for targets above the consolidation threshold — writes the
/// `Derived/FrameworkSearchPaths/<Target>.resp` response file those settings reference.
///
/// It must run after the binary-cache replacement mappers so it sees the precompiled xcframework
/// dependencies, and its `.resp` side effect must land in the same batch as
/// `DeleteDerivedDirectoryProjectMapper`'s cleanup, after the deletes, so the file is not removed
/// once written — the same way `ModuleMapMapper` writes the dependency module maps.
public struct FrameworkSearchPathsGraphMapper: GraphMapping {
    /// Targets with at least this many unique precompiled framework search paths get those paths
    /// consolidated into a response file to keep C/ObjC compilation and linking under ARG_MAX.
    private static let consolidationThreshold = 20

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

        var settingsByTarget: [TargetID: [(key: String, values: [String])]] = [:]
        var sideEffects: [SideEffectDescriptor] = []

        for (_, project) in graph.projects {
            for (_, target) in project.targets {
                let linkableModules = try graphTraverser
                    .searchablePathDependencies(path: project.path, name: target.name).sorted()

                let precompiledPaths = Set(linkableModules.compactMap(\.precompiledPath)
                    .map { LinkGeneratorPath.absolutePath($0.removingLastComponent()) })
                let sdkPaths = Set(linkableModules.compactMap { (dependency: GraphDependencyReference) -> LinkGeneratorPath? in
                    if case let GraphDependencyReference.sdk(_, _, source, _) = dependency {
                        return source.frameworkSearchPath.map { LinkGeneratorPath.string($0) }
                    } else {
                        return nil
                    }
                })

                guard !precompiledPaths.isEmpty || !sdkPaths.isEmpty else { continue }

                var additions: [(key: String, values: [String])] = []
                if precompiledPaths.count >= Self.consolidationThreshold {
                    let responseFilePath = project.sourceRootPath.appending(
                        components: Constants.DerivedDirectory.name,
                        Constants.DerivedDirectory.frameworkSearchPaths,
                        "\(target.name).resp"
                    )
                    let precompiledXcodeValues = precompiledPaths
                        .map { $0.xcodeValue(sourceRootPath: project.sourceRootPath) }
                        .uniqued()
                        .sorted()
                    // The response file must contain absolute paths since clang doesn't expand build
                    // setting variables. Convert $(SRCROOT)/... to absolute paths.
                    let responseFileContents = precompiledXcodeValues
                        .map { "-F" + $0.replacingOccurrences(of: "$(SRCROOT)", with: project.sourceRootPath.pathString) }
                        .joined(separator: "\n")
                        + "\n"
                    sideEffects.append(
                        .file(FileDescriptor(path: responseFilePath, contents: Data(responseFileContents.utf8)))
                    )

                    let responseFileReference = "@$(SRCROOT)/\(responseFilePath.relative(to: project.sourceRootPath))"
                    // FRAMEWORK_SEARCH_PATHS keeps only the SDK paths; clang and ld read the precompiled
                    // paths from the response file via @file to stay under ARG_MAX.
                    additions.append((
                        Self.frameworkSearchPathsSetting,
                        xcodeValues(of: sdkPaths, sourceRootPath: project.sourceRootPath)
                    ))
                    additions.append((Self.otherCFlagsSetting, [responseFileReference]))
                    // OTHER_SWIFT_FLAGS gets inline -F flags instead of @file: Swift has no ARG_MAX
                    // problem here and the Xcode 26 ClangImporter / integrated SwiftDriver mishandle a
                    // @file token.
                    additions.append((Self.otherSwiftFlagsSetting, precompiledXcodeValues.flatMap { ["-F", $0] }))
                    additions.append((Self.otherLinkerFlagsSetting, [responseFileReference]))
                } else {
                    additions.append((
                        Self.frameworkSearchPathsSetting,
                        xcodeValues(of: precompiledPaths.union(sdkPaths), sourceRootPath: project.sourceRootPath)
                    ))
                }

                settingsByTarget[TargetID(projectPath: project.path, targetName: target.name)] = additions
            }
        }

        var graph = graph
        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { targetName, target in
                guard let additions = settingsByTarget[TargetID(projectPath: project.path, targetName: target.name)]
                else { return (targetName, target) }
                var target = target
                target.settings = apply(additions, to: target.settings, defaultSettings: project.settings.defaultSettings)
                return (target.name, target)
            })
            return (projectPath, project)
        })

        return (graph, sideEffects, environment)
    }

    private func xcodeValues(of paths: Set<LinkGeneratorPath>, sourceRootPath: AbsolutePath) -> [String] {
        paths.map { $0.xcodeValue(sourceRootPath: sourceRootPath) }.uniqued().sorted()
    }

    /// Applies the settings to the target's base settings and to any configuration that already
    /// overrides one of the affected keys. Configuration-level keys shadow the base value entirely,
    /// so patching only the base would drop the flags for targets that override e.g.
    /// `OTHER_SWIFT_FLAGS` per configuration (mirrors `ModuleMapMapper`).
    private func apply(
        _ additions: [(key: String, values: [String])],
        to settings: Settings?,
        defaultSettings: DefaultSettings
    ) -> Settings {
        let settings = settings ?? Settings(base: [:], configurations: [:], defaultSettings: defaultSettings)
        return Settings(
            base: applied(additions, to: settings.base),
            baseDebug: settings.baseDebug,
            configurations: settings.configurations.mapValues { configuration in
                guard let configuration else { return nil }
                return configuration.with(settings: applied(additions, to: configuration.settings, onlyExistingKeys: true))
            },
            defaultSettings: settings.defaultSettings,
            defaultConfiguration: settings.defaultConfiguration
        )
    }

    private func applied(
        _ additions: [(key: String, values: [String])],
        to settings: SettingsDictionary,
        onlyExistingKeys: Bool = false
    ) -> SettingsDictionary {
        var settings = settings
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
