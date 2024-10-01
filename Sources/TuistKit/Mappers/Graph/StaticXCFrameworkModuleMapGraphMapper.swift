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
    private let manifestFilesLocator: ManifestFilesLocating

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.fileHandler = fileHandler
        self.manifestFilesLocator = manifestFilesLocator
    }

    public func map(graph: Graph, environment: MapperEnvironment) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        guard let packageManifest = manifestFilesLocator.locatePackageManifest(at: graph.path)
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

        let graph = try mapGraph(
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

            sideEffects += try generateModuleMapAndUmbrellaHeader(
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
                        .map {
                            "\"$(SRCROOT)/\($0.primaryBinaryPath.parentDirectory.parentDirectory.relative(to: project.path).pathString)\""
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
                        guard let moduleMap = xcframework.path.glob("**/module.modulemap").first
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
    ) throws -> [SideEffectDescriptor] {
        try staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies
            .flatMap { xcframework -> [SideEffectDescriptor] in
                guard let moduleMap = xcframework.path.glob("**/module.modulemap").first
                else { return [] }
                let name = xcframework.path.basenameWithoutExt
                let umbrellaHeader = xcframework.path.glob("**/\(name).h").first
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
        targetSettings: (GraphTarget) throws -> SettingsDictionary
    ) throws -> Graph {
        var graph = graph
        var settings: [GraphDependency: SettingsDictionary] = [:]
        let targets = try GraphTraverser(graph: graph).allTargetsTopologicalSorted()
        for target in targets {
            guard let dependencies = graph.dependencies[.target(name: target.target.name, path: target.path)] else { continue }
            let targetDependency: GraphDependency = .target(name: target.target.name, path: target.path)
            settings[targetDependency] = try targetSettings(target)
            for dependency in dependencies {
                settings[targetDependency] = (settings[targetDependency] ?? [:]).combine(with: settings[dependency] ?? [:])
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
                )
                return target
            }
            return project
        }
        return graph
    }
}

extension GraphDependency.XCFramework {
    fileprivate func containsLibrary() -> Bool {
        infoPlist.libraries
            .contains(where: { $0.path.extension == "a" })
    }
}
