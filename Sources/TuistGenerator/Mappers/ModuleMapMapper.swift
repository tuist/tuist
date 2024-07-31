import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

/// Mapper that maps the `MODULE_MAP` build setting to the `-fmodule-map-file` compiler flags.
/// It is required to avoid embedding the module map into the frameworks during cache operations, which would make the framework
/// not portable, as the modulemap could contain absolute paths.
public final class ModuleMapMapper: GraphMapping { // swiftlint:disable:this type_body_length
    private static let modulemapFileSetting = "MODULEMAP_FILE"
    private static let otherCFlagsSetting = "OTHER_CFLAGS"
    private static let otherSwiftFlagsSetting = "OTHER_SWIFT_FLAGS"
    private static let headerSearchPaths = "HEADER_SEARCH_PATHS"

    private struct TargetID: Hashable {
        let projectPath: AbsolutePath
        let targetName: String
    }

    private struct DependencyMetadata: Hashable {
        let moduleMapPath: AbsolutePath?
        let headerSearchPaths: [String]
    }

    public init() {}

    // swiftlint:disable function_body_length
    public func map(graph: Graph, environment: MapperEnvironment) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        logger
            .debug(
                "Transforming graph \(graph.name): Mapping MODULE_MAP build setting to -fmodule-map-file compiler flag"
            )

        var targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>] = [:]
        let graphTraverser = GraphTraverser(graph: graph)
        for target in graphTraverser.allTargets() {
            try Self.dependenciesModuleMaps(
                graph: graph,
                target: target,
                targetToDependenciesMetadata: &targetToDependenciesMetadata
            )
        }

        var graph = graph

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { targetName, target in
                var target = target
                let targetID = TargetID(projectPath: project.path, targetName: target.name)
                var mappedSettingsDictionary = target.settings?.base ?? [:]
                let hasModuleMap = mappedSettingsDictionary[Self.modulemapFileSetting] != nil
                guard hasModuleMap || !(targetToDependenciesMetadata[targetID]?.isEmpty ?? true)
                else { return (targetName, target) }

                if hasModuleMap {
                    mappedSettingsDictionary[Self.modulemapFileSetting] = nil
                }

                if let updatedOtherSwiftFlags = Self.updatedOtherSwiftFlags(
                    targetID: targetID,
                    oldOtherSwiftFlags: mappedSettingsDictionary[Self.otherSwiftFlagsSetting],
                    targetToDependenciesMetadata: targetToDependenciesMetadata
                ) {
                    mappedSettingsDictionary[Self.otherSwiftFlagsSetting] = updatedOtherSwiftFlags
                }

                if let updatedOtherCFlags = Self.updatedOtherCFlags(
                    targetID: targetID,
                    oldOtherCFlags: mappedSettingsDictionary[Self.otherCFlagsSetting],
                    targetToDependenciesMetadata: targetToDependenciesMetadata
                ) {
                    mappedSettingsDictionary[Self.otherCFlagsSetting] = updatedOtherCFlags
                }

                if let updatedHeaderSearchPaths = Self.updatedHeaderSearchPaths(
                    targetID: targetID,
                    oldHeaderSearchPaths: mappedSettingsDictionary[Self.headerSearchPaths],
                    targetToDependenciesMetadata: targetToDependenciesMetadata
                ) {
                    mappedSettingsDictionary[Self.headerSearchPaths] = updatedHeaderSearchPaths
                }

                let targetSettings = target.settings ?? Settings(
                    base: [:],
                    configurations: [:],
                    defaultSettings: project.settings.defaultSettings
                )
                target.settings = targetSettings.with(base: mappedSettingsDictionary)

                return (target.name, target)
            })

            return (projectPath, project)
        })
        return (graph, [], environment)
    } // swiftlint:enable function_body_length

    private static func makeProjectsByPathWithTargetsByName(workspace: WorkspaceWithProjects)
        -> ([AbsolutePath: Project], [String: Target])
    {
        var projectsByPath = [AbsolutePath: Project]()
        var targetsByName = [String: Target]()
        for project in workspace.projects {
            projectsByPath[project.path] = project
            for target in project.targets.values {
                targetsByName[target.name] = target
            }
        }
        return (projectsByPath, targetsByName)
    }

    /// Calculates the set of module maps to be linked to a given target and populates the `targetToDependenciesMetadata`
    /// dictionary.
    /// Each target must link the module map of its direct and indirect dependencies.
    /// The `targetToDependenciesMetadata` is also used as cache to avoid recomputing the set for already computed targets.
    private static func dependenciesModuleMaps( // swiftlint:disable:this function_body_length
        graph: Graph,
        target: GraphTarget,
        targetToDependenciesMetadata: inout [TargetID: Set<DependencyMetadata>]
    ) throws {
        let targetID = TargetID(projectPath: target.path, targetName: target.target.name)
        if targetToDependenciesMetadata[targetID] != nil {
            // already computed
            return
        }

        let graphTraverser = GraphTraverser(graph: graph)

        var dependenciesMetadata: Set<DependencyMetadata> = []
        for dependency in graphTraverser.directTargetDependencies(path: target.path, name: target.target.name) {
            try Self.dependenciesModuleMaps(
                graph: graph,
                target: dependency.graphTarget,
                targetToDependenciesMetadata: &targetToDependenciesMetadata
            )

            // direct dependency module map
            let dependencyModuleMapPath: AbsolutePath?

            if case let .string(dependencyModuleMap) = dependency.target.settings?.base[Self.modulemapFileSetting] {
                let pathString = dependency.graphTarget.path.pathString
                dependencyModuleMapPath = try AbsolutePath(
                    validating: dependencyModuleMap
                        .replacingOccurrences(of: "$(PROJECT_DIR)", with: pathString)
                        .replacingOccurrences(of: "$(SRCROOT)", with: pathString)
                        .replacingOccurrences(of: "$(SOURCE_ROOT)", with: pathString)
                )
            } else {
                dependencyModuleMapPath = nil
            }

            var headerSearchPaths: [String]
            switch dependency.target.settings?.base[Self.headerSearchPaths] ?? .array([]) {
            case let .array(values):
                headerSearchPaths = values
            case let .string(value):
                headerSearchPaths = [value]
            }

            headerSearchPaths = headerSearchPaths.map {
                let pathString = dependency.graphTarget.path.pathString
                return (
                    try? AbsolutePath(
                        validating: $0
                            .replacingOccurrences(of: "$(PROJECT_DIR)", with: pathString)
                            .replacingOccurrences(of: "$(SRCROOT)", with: pathString)
                            .replacingOccurrences(of: "$(SOURCE_ROOT)", with: pathString)
                    ).pathString
                ) ?? $0
            }

            // indirect dependency module maps
            let dependentTargetID = TargetID(projectPath: dependency.graphTarget.path, targetName: dependency.target.name)
            if let indirectDependencyMetadata = targetToDependenciesMetadata[dependentTargetID] {
                dependenciesMetadata.formUnion(indirectDependencyMetadata)
            }

            dependenciesMetadata.insert(
                DependencyMetadata(
                    moduleMapPath: dependencyModuleMapPath,
                    headerSearchPaths: headerSearchPaths
                )
            )
        }

        targetToDependenciesMetadata[targetID] = dependenciesMetadata
    }

    private static func updatedHeaderSearchPaths(
        targetID: TargetID,
        oldHeaderSearchPaths: SettingsDictionary.Value?,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>]
    ) -> SettingsDictionary.Value? {
        let dependenciesHeaderSearchPaths = Set(targetToDependenciesMetadata[targetID]?.flatMap(\.headerSearchPaths) ?? [])
        guard !dependenciesHeaderSearchPaths.isEmpty
        else { return nil }

        var mappedHeaderSearchPaths: [String]
        switch oldHeaderSearchPaths ?? .array(["$(inherited)"]) {
        case let .array(values):
            mappedHeaderSearchPaths = values
        case let .string(value):
            mappedHeaderSearchPaths = value.split(separator: " ").map(String.init)
        }

        for headerSearchPath in dependenciesHeaderSearchPaths.sorted() {
            mappedHeaderSearchPaths.append(
                (
                    try? AbsolutePath(validating: headerSearchPath)
                        .relative(to: targetID.projectPath).pathString
                ).map { "$(SRCROOT)/\($0)" } ?? headerSearchPath
            )
        }

        return .array(mappedHeaderSearchPaths)
    }

    private static func updatedOtherSwiftFlags(
        targetID: TargetID,
        oldOtherSwiftFlags: SettingsDictionary.Value?,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>]
    ) -> SettingsDictionary.Value? {
        guard let dependenciesModuleMaps = targetToDependenciesMetadata[targetID]?.compactMap(\.moduleMapPath),
              !dependenciesModuleMaps.isEmpty
        else { return nil }

        var mappedOtherSwiftFlags: [String]
        switch oldOtherSwiftFlags ?? .array(["$(inherited)"]) {
        case let .array(values):
            mappedOtherSwiftFlags = values
        case let .string(value):
            mappedOtherSwiftFlags = value.split(separator: " ").map(String.init)
        }

        for moduleMap in dependenciesModuleMaps.sorted() {
            mappedOtherSwiftFlags.append(contentsOf: [
                "-Xcc",
                "-fmodule-map-file=$(SRCROOT)/\(moduleMap.relative(to: targetID.projectPath))",
            ])
        }

        return .array(mappedOtherSwiftFlags)
    }

    private static func updatedOtherCFlags(
        targetID: TargetID,
        oldOtherCFlags: SettingsDictionary.Value?,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>]
    ) -> SettingsDictionary.Value? {
        guard let dependenciesModuleMaps = targetToDependenciesMetadata[targetID]?.compactMap(\.moduleMapPath),
              !dependenciesModuleMaps.isEmpty
        else { return nil }

        var mappedOtherCFlags: [String]
        switch oldOtherCFlags ?? .array(["$(inherited)"]) {
        case let .array(values):
            mappedOtherCFlags = values
        case let .string(value):
            mappedOtherCFlags = value.split(separator: " ").map(String.init)
        }

        for moduleMap in dependenciesModuleMaps.sorted() {
            mappedOtherCFlags.append("-fmodule-map-file=$(SRCROOT)/\(moduleMap.relative(to: targetID.projectPath))")
        }

        return .array(mappedOtherCFlags)
    }
}
