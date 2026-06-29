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
    /// consolidated into a response file to keep C, Objective-C, and linking command lines short.
    private static let consolidationThreshold = 20

    private static let frameworkSearchPathsSetting = "FRAMEWORK_SEARCH_PATHS"
    private static let otherCFlagsSetting = "OTHER_CFLAGS"
    private static let otherSwiftFlagsSetting = "OTHER_SWIFT_FLAGS"
    private static let otherLinkerFlagsSetting = "OTHER_LDFLAGS"

    private struct TargetID: Hashable {
        let projectPath: AbsolutePath
        let targetName: String
    }

    private struct PrecompiledArtifact: Hashable {
        let path: AbsolutePath

        var searchPath: LinkGeneratorPath {
            .absolutePath(path.removingLastComponent())
        }

        var canBeLinkedIntoSwiftSearchPath: Bool {
            path.extension == "framework" || path.extension == "xcframework"
        }
    }

    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        Logger.current.debug("Transforming graph \(graph.name): Setting up framework search paths")

        let graphTraverser = GraphTraverser(graph: graph)

        var settingsByTarget: [TargetID: [(key: String, values: [String])]] = [:]
        var generatedFileSideEffects: [SideEffectDescriptor] = []
        var generatedSymbolicLinkSideEffects: [SideEffectDescriptor] = []
        var generatedResponseFileDirectories: Set<AbsolutePath> = []
        var activeFilesByDirectory: [AbsolutePath: Set<AbsolutePath>] = [:]
        var activeFrameworkLinksByDirectory: [AbsolutePath: Set<AbsolutePath>] = [:]

        for (_, project) in graph.projects {
            let responseFileDirectory = project.sourceRootPath.appending(
                components: Constants.DerivedDirectory.name,
                Constants.DerivedDirectory.frameworkSearchPaths
            )
            generatedResponseFileDirectories.insert(responseFileDirectory)

            for (_, target) in project.targets {
                let linkableModules = try graphTraverser
                    .searchablePathDependencies(path: project.path, name: target.name).sorted()

                let precompiledArtifacts = Set(linkableModules.compactMap(\.precompiledPath).map(PrecompiledArtifact.init))
                let precompiledPaths = Set(precompiledArtifacts.map(\.searchPath))
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
                    let responseFilePath = responseFileDirectory.appending(component: "\(target.name).resp")
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
                    activeFilesByDirectory[responseFileDirectory, default: []].insert(responseFilePath)
                    generatedFileSideEffects.append(
                        .file(FileDescriptor(path: responseFilePath, contents: Data(responseFileContents.utf8)))
                    )

                    let responseFileReference = "\"@$(SRCROOT)/\(responseFilePath.relative(to: project.sourceRootPath))\""
                    let swiftFrameworkSearchPath = responseFileDirectory.appending(
                        components: "Swift",
                        target.name
                    )
                    let swiftSearchPathAdditions = swiftSearchPathValues(
                        precompiledArtifacts: precompiledArtifacts,
                        swiftFrameworkSearchPath: swiftFrameworkSearchPath,
                        cleanupDirectory: responseFileDirectory,
                        sourceRootPath: project.sourceRootPath,
                        activeFrameworkLinksByDirectory: &activeFrameworkLinksByDirectory,
                        generatedSymbolicLinkSideEffects: &generatedSymbolicLinkSideEffects
                    )
                    // FRAMEWORK_SEARCH_PATHS keeps only platform framework paths; Clang and the linker read the
                    // precompiled paths from the response file via @file to keep command lines short.
                    additions.append((
                        Self.frameworkSearchPathsSetting,
                        xcodeValues(of: sdkPaths, sourceRootPath: project.sourceRootPath)
                    ))
                    additions.append((Self.otherCFlagsSetting, [responseFileReference]))
                    // OTHER_SWIFT_FLAGS gets -F flags instead of @file because the Xcode 26 ClangImporter and
                    // integrated SwiftDriver mishandle a @file token.
                    additions.append((Self.otherSwiftFlagsSetting, swiftSearchPathAdditions.flatMap { ["-F", $0] }))
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

        var sideEffects: [SideEffectDescriptor] = generatedResponseFileDirectories.isEmpty ? [] : [
            .generatedFilesCleanup(
                GeneratedFilesCleanupDescriptor(
                    directories: generatedResponseFileDirectories,
                    activeFilesByDirectory: activeFilesByDirectory,
                    include: ["*.resp"]
                )
            ),
        ]
        if !activeFrameworkLinksByDirectory.isEmpty {
            sideEffects.append(
                .generatedFilesCleanup(
                    GeneratedFilesCleanupDescriptor(
                        directories: Set(activeFrameworkLinksByDirectory.keys),
                        activeFilesByDirectory: activeFrameworkLinksByDirectory,
                        include: ["**/*.framework", "**/*.xcframework"]
                    )
                )
            )
        }
        sideEffects.append(contentsOf: generatedFileSideEffects)
        sideEffects.append(contentsOf: generatedSymbolicLinkSideEffects)
        return (graph, sideEffects, environment)
    }

    private func xcodeValues(of paths: Set<LinkGeneratorPath>, sourceRootPath: AbsolutePath) -> [String] {
        paths.map { $0.xcodeValue(sourceRootPath: sourceRootPath) }.uniqued().sorted()
    }

    private func swiftSearchPathValues(
        precompiledArtifacts: Set<PrecompiledArtifact>,
        swiftFrameworkSearchPath: AbsolutePath,
        cleanupDirectory: AbsolutePath,
        sourceRootPath: AbsolutePath,
        activeFrameworkLinksByDirectory: inout [AbsolutePath: Set<AbsolutePath>],
        generatedSymbolicLinkSideEffects: inout [SideEffectDescriptor]
    ) -> [String] {
        let frameworkArtifacts = precompiledArtifacts.filter(\.canBeLinkedIntoSwiftSearchPath)
        let frameworkArtifactsByBasename = Dictionary(grouping: frameworkArtifacts, by: \.path.basename)

        let linkableArtifacts = frameworkArtifactsByBasename.values
            .filter { $0.count == 1 }
            .compactMap(\.first)
            .sorted { $0.path.pathString < $1.path.pathString }
        let conflictingFrameworkSearchPaths = frameworkArtifactsByBasename.values
            .filter { $0.count > 1 }
            .flatMap { $0.map(\.searchPath) }
        let unsupportedSearchPaths = precompiledArtifacts
            .filter { !$0.canBeLinkedIntoSwiftSearchPath }
            .map(\.searchPath)

        var values: [String] = []
        if !linkableArtifacts.isEmpty {
            values.append(LinkGeneratorPath.absolutePath(swiftFrameworkSearchPath).xcodeValue(sourceRootPath: sourceRootPath))
            let linkPaths = Set(linkableArtifacts.map { artifact in
                swiftFrameworkSearchPath.appending(component: artifact.path.basename)
            })
            activeFrameworkLinksByDirectory[cleanupDirectory, default: []].formUnion(linkPaths)
            generatedSymbolicLinkSideEffects.append(
                contentsOf: linkableArtifacts.map { artifact in
                    .symbolicLink(
                        SymbolicLinkDescriptor(
                            path: swiftFrameworkSearchPath.appending(component: artifact.path.basename),
                            destination: artifact.path
                        )
                    )
                }
            )
        }

        values.append(
            contentsOf: xcodeValues(
                of: Set(conflictingFrameworkSearchPaths + unsupportedSearchPaths),
                sourceRootPath: sourceRootPath
            )
        )

        return values
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
