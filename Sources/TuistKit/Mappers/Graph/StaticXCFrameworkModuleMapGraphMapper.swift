import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

public final class StaticXCFrameworkModuleMapGraphMapper: GraphMapping {
    private let fileHandler: FileHandling

    public init(
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.fileHandler = fileHandler
    }

    public func map(graph: Graph, environment: MapperEnvironment) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let derivedDirectory = derivedDirectory(graph: graph)

        var sideEffects: [SideEffectDescriptor] = []
        var settingsToPropagate: [GraphDependency: SettingsDictionary] = [:]

        let graphTraverser = GraphTraverser(graph: graph)

        for project in graph.projects.values {
            for target in project.targets.values {
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

                guard !staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies.isEmpty else { continue }

                sideEffects += try self.sideEffects(
                    for: staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies,
                    derivedDirectory: derivedDirectory
                )

                settingsToPropagate[.target(name: target.name, path: project.path)] = [
                    "OTHER_SWIFT_FLAGS": .array(
                        staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                            [
                                "-Xcc",
                                moduleMapFlag(
                                    for: xcframework,
                                    derivedDirectory: derivedDirectory,
                                    project: project
                                ),
                            ]
                        }
                    ),
                    "OTHER_C_FLAGS": .array(
                        staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                            [
                                moduleMapFlag(
                                    for: xcframework,
                                    derivedDirectory: derivedDirectory,
                                    project: project
                                ),
                            ]
                        }
                    ),
                    "HEADER_SEARCH_PATHS": .array(
                        staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies.flatMap { xcframework -> [String] in
                            guard let moduleMap = xcframework.path.glob("**/module.modulemap").first
                            else { return [] }
                            return [
                                "\"$(SRCROOT)/\(moduleMap.parentDirectory.relative(to: project.path).pathString)\"",
                            ]
                        }
                    ),
                ]
            }
        }

        return (
            try propagateSettings(graph: graph, settings: settingsToPropagate),
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

    private func derivedDirectory(graph: Graph) -> AbsolutePath {
        let packageDirectoryPath: AbsolutePath
        if fileHandler.exists(graph.path.appending(component: Constants.SwiftPackageManager.packageSwiftName)) {
            packageDirectoryPath = graph.path
        } else {
            packageDirectoryPath = graph.path.appending(component: Constants.tuistDirectoryName)
        }

        return packageDirectoryPath
            .appending(
                components: [
                    Constants.SwiftPackageManager.packageBuildDirectoryName,
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                ]
            )
    }

    private func sideEffects(
        for staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies: [GraphDependency.XCFramework],
        derivedDirectory: AbsolutePath
    ) throws -> [SideEffectDescriptor] {
        try staticObjcXCFrameworksLinkedByDynamicXCFrameworkDependencies
            .flatMap { xcframework -> [SideEffectDescriptor] in
                guard let moduleMap = xcframework.path.glob("**/module.modulemap").first
                else { return [] }
                let name = xcframework.path.basenameWithoutExt
                let umbrellaHeader = moduleMap.parentDirectory.appending(component: "\(name).h")
                guard fileHandler.exists(umbrellaHeader)
                else { return [] }
                return [
                    .directory(DirectoryDescriptor(path: derivedDirectory.appending(components: name, "Headers"))),
                    .file(
                        FileDescriptor(
                            path: derivedDirectory.appending(components: name, "Headers", "module.modulemap"),
                            contents: try fileHandler.readFile(moduleMap)
                        )
                    ),
                    .file(
                        FileDescriptor(
                            path: derivedDirectory.appending(components: name, "Headers", "\(name).h"),
                            contents: String(data: try fileHandler.readFile(umbrellaHeader), encoding: .utf8)?
                                .replacingOccurrences(of: "<\(name)/", with: "<")
                                .data(using: .utf8)
                        )
                    ),
                ]
            }
    }

    private func propagateSettings(
        graph: Graph,
        settings: [GraphDependency: SettingsDictionary]
    ) throws -> Graph {
        var graph = graph
        var settings = settings
        let targets = try GraphTraverser(graph: graph).allTargetsTopologicalSorted()
        for target in targets {
            guard let dependencies = graph.dependencies[.target(name: target.target.name, path: target.path)] else { continue }
            for dependency in dependencies {
                let targetDependency: GraphDependency = .target(name: target.target.name, path: target.path)
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
