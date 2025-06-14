import FileSystem
import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

/// This mapper sets the right setting for downstream targets that depend on static xcframeworks linked by dynamic
/// xcframeworks.
/// See this PR for more context: https://github.com/tuist/tuist/pull/6757
public final class StaticXCFrameworkModuleMapGraphMapper: GraphMapping {
    private let fileHandler: FileHandling
    private let fileSystem: FileSysteming
    private let manifestFilesLocator: ManifestFilesLocating

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        fileSystem: FileSysteming = FileSystem(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.fileHandler = fileHandler
        self.fileSystem = fileSystem
        self.manifestFilesLocator = manifestFilesLocator
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        guard let packageManifest = try await manifestFilesLocator.locatePackageManifest(at: graph.path)
        else { return (graph, [], environment) }
        let derivedDirectory = packageManifest
            .parentDirectory
            .appending(
                components: [
                    Constants.SwiftPackageManager.packageBuildDirectoryName,
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                ]
            )

        var sideEffects: [SideEffectDescriptor] = []
        let graphTraverser = GraphTraverser(graph: graph)

        let graph = try await mapGraph(
            graph: graph
        ) { graphTarget in
            let target = graphTarget.target
            let project = graphTarget.project
            let staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies = graphTraverser
                .staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies(
                    path: project.path,
                    name: target.name
                )
                .compactMap { dependency -> GraphDependency.XCFramework? in
                    switch dependency {
                    case let .xcframework(xcframework):
                        return xcframework
                    default:
                        return nil
                    }
                }

            guard !staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies.isEmpty else { return [:] }

            let staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies =
                staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies
                    .filter { $0.containsLibrary() }

            sideEffects += try await generateModuleMapAndUmbrellaHeader(
                for: staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies,
                derivedDirectory: derivedDirectory
            )

            let staticObjcXCFrameworksWithoutLibrariesLinkedByDynamicXCFrameworkDependencies =
                staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies
                    .filter { !$0.containsLibrary() }

            var settings = SettingsDictionary()
            if !staticObjcXCFrameworksWithoutLibrariesLinkedByDynamicXCFrameworkDependencies.isEmpty {
                settings["FRAMEWORK_SEARCH_PATHS"] = .array(
                    staticObjcXCFrameworksWithoutLibrariesLinkedByDynamicXCFrameworkDependencies
                        .compactMap {
                            if let library = $0.infoPlist.libraries
                                .first(where: { target.supportedPlatforms.contains($0.platform.graphPlatform) })
                            {
                                return "\"$(SRCROOT)/\($0.path.appending(component: library.identifier).relative(to: project.path).pathString)\""
                            } else {
                                return nil
                            }
                        }
                )
            }

            if !staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies.isEmpty {
                settings["OTHER_SWIFT_FLAGS"] = .array(
                    staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                        [
                            "-Xcc",
                            moduleMapFlag(
                                for: xcframework,
                                derivedDirectory: derivedDirectory,
                                project: project
                            ),
                        ]
                    }
                )
                settings["OTHER_C_FLAGS"] = .array(
                    staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                        [
                            moduleMapFlag(
                                for: xcframework,
                                derivedDirectory: derivedDirectory,
                                project: project
                            ),
                        ]
                    }
                )
                settings["HEADER_SEARCH_PATHS"] = .array(
                    staticObjcXCFrameworksWithLibrariesLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                        guard let moduleMap = xcframework.moduleMaps.first
                        else { return [] }
                        return [
                            "\"$(SRCROOT)/\(moduleMap.parentDirectory.relative(to: project.path).pathString)\"",
                        ]
                    }
                )
            }

            return settings
        }

        return (
            graph,
            sideEffects,
            environment
        )
    }

    private func moduleMapFlag(
        for xcframework: GraphDependency.XCFramework,
        derivedDirectory: AbsolutePath,
        project: Project
    ) -> String {
        let name = xcframework.path.basenameWithoutExt
        return "-fmodule-map-file=\"$(SRCROOT)/\(derivedDirectory.appending(components: name, "Headers", "module.modulemap").relative(to: project.path).pathString)\""
    }

    /// Generates modulemap and an umbrella header that can be referenced from downstream targets.
    private func generateModuleMapAndUmbrellaHeader(
        for staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies: [GraphDependency.XCFramework],
        derivedDirectory: AbsolutePath
    ) async throws -> [SideEffectDescriptor] {
        let fileSystem = fileSystem
        let fileHandler = fileHandler
        return try await staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies
            .concurrentFlatMap { xcframework -> [SideEffectDescriptor] in
                guard let moduleMap = xcframework.moduleMaps.first
                else { return [] }
                let name = xcframework.path.basenameWithoutExt
                let umbrellaHeader = try await fileSystem.glob(directory: xcframework.path, include: ["**/\(name).h"]).collect()
                    .first
                let headersDirectory = derivedDirectory.appending(components: name, "Headers")
                var sideEffects: [SideEffectDescriptor] = [
                    .directory(DirectoryDescriptor(path: headersDirectory)),
                    .file(
                        FileDescriptor(
                            path: headersDirectory.appending(components: "module.modulemap"),
                            contents: try fileHandler.readFile(moduleMap)
                        )
                    ),
                ]

                if let umbrellaHeader {
                    sideEffects.append(
                        .file(
                            FileDescriptor(
                                path: headersDirectory.appending(components: "\(name).h"),
                                contents: String(data: try fileHandler.readFile(umbrellaHeader), encoding: .utf8)?
                                    .replacingOccurrences(of: "<\(name)/", with: "<")
                                    .data(using: .utf8)
                            )
                        )
                    )
                }

                return sideEffects
            }
    }

    private func mapGraph(
        graph: Graph,
        targetSettings: (GraphTarget) async throws -> SettingsDictionary
    ) async throws -> Graph {
        var graph = graph
        var settings: [GraphDependency: SettingsDictionary] = [:]
        let targets = try GraphTraverser(graph: graph).allTargetsTopologicalSorted()
        for target in targets {
            guard let dependencies = graph.dependencies[.target(name: target.target.name, path: target.path)] else { continue }
            let targetDependency: GraphDependency = .target(name: target.target.name, path: target.path)
            settings[targetDependency] = try await targetSettings(target)
            for dependency in dependencies {
                settings[targetDependency] = (settings[targetDependency] ?? [:])
                    .combine(with: settings[dependency] ?? [:])
                    .removeDuplicates()
            }
        }
        graph.projects = graph.projects.mapValues { project in
            var project = project
            project.targets = project.targets.mapValues { target in
                var target = target
                let targetSettings = target.settings ?? Settings(
                    base: [:],
                    configurations: [:],
                    defaultSettings: project.settings.defaultSettings
                )
                target.settings = targetSettings.with(
                    base: targetSettings.base
                        .combine(with: settings[.target(name: target.name, path: project.path)] ?? SettingsDictionary())
                        .removeDuplicates()
                )
                return target
            }
            return project
        }
        return graph
    }
}

extension SettingsDictionary {
    /// There are scenarios when the combined settings introduce duplicates for these setting keys.
    /// We don't know how to reproduce – either in a reproducible sample or via unit tests.
    /// This is also why the `removeOtherSwiftFlagsDuplicates` is `internal` instead of `fileprivate`, so we can at least test the
    /// method itself in isolation.
    fileprivate func removeDuplicates() -> SettingsDictionary {
        removeDuplicates(for: "FRAMEWORK_SEARCH_PATHS")
            .removeDuplicates(for: "HEADER_SEARCH_PATHS")
            .removeDuplicates(for: "OTHER_C_FLAGS")
            .removeOtherSwiftFlagsDuplicates()
    }

    func removeOtherSwiftFlagsDuplicates() -> SettingsDictionary {
        let key = "OTHER_SWIFT_FLAGS"
        var settings = self
        guard let value = settings[key] else { return settings }
        switch value {
        case let .string(value):
            settings[key] = .string(value)
        case let .array(value):
            var seen = Set<String>()
            let value = value.enumerated().filter {
                if $0.element.starts(with: "-X") || $0.element == "-I" {
                    if value.endIndex > $0.offset + 1 {
                        return !seen.contains($0.element + value[$0.offset + 1])
                    } else {
                        return true
                    }
                } else {
                    if $0.offset == 0 {
                        return seen.insert($0.element).inserted
                    } else {
                        let previousElement = value[$0.offset - 1]
                        if previousElement.starts(with: "-X") || previousElement == "-I" {
                            return seen.insert(previousElement + $0.element).inserted
                        } else {
                            return seen.insert($0.element).inserted
                        }
                    }
                }
            }
            settings[key] = .array(
                value.map(\.element)
            )
        }
        return settings
    }

    fileprivate func removeDuplicates(for key: String) -> SettingsDictionary {
        var settings = self
        guard let value = settings[key] else { return settings }
        switch value {
        case let .string(value):
            settings[key] = .string(value)
        case let .array(value):
            settings[key] = .array(
                value.uniqued()
            )
        }
        return settings
    }
}

extension XCFrameworkInfoPlist.Library.Platform {
    fileprivate var graphPlatform: XcodeGraph.Platform {
        switch self {
        case .iOS: return .iOS
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        case .watchOS: return .watchOS
        case .visionOS: return .visionOS
        }
    }
}

extension GraphDependency.XCFramework {
    fileprivate func containsLibrary() -> Bool {
        infoPlist.libraries
            .contains(where: { $0.path.extension == "a" })
    }
}
