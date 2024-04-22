import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

enum ModuleMapMapperError: FatalError {
    case invalidTargetDependency(sourceProject: AbsolutePath, sourceTarget: String, dependentTarget: String)
    case invalidProjectTargetDependency(
        sourceProject: AbsolutePath,
        sourceTarget: String,
        dependentProject: AbsolutePath,
        dependentTarget: String
    )

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidTargetDependency, .invalidProjectTargetDependency: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .invalidTargetDependency(sourceProject, sourceTarget, dependentTarget):
            return """
            Target '\(sourceTarget)' of the project at path '\(sourceProject.pathString)' \
            depends on a target '\(dependentTarget)' that can't be found. \
            Please make sure your project configuration is correct.
            """
        case let .invalidProjectTargetDependency(sourceProject, sourceTarget, dependentProject, dependentTarget):
            return """
            Target '\(sourceTarget)' of the project at path '\(sourceProject.pathString)' \
            depends on a target '\(dependentTarget)' of the project at path '\(
                dependentProject
                    .pathString
            )' that can't be found. \
            Please make sure your project configuration is correct.
            """
        }
    }
}

/// Mapper that maps the `MODULE_MAP` build setting to the `-fmodule-map-file` compiler flags.
/// It is required to avoid embedding the module map into the frameworks during cache operations, which would make the framework
/// not portable, as the modulemap could contain absolute paths.
public final class ModuleMapMapper: GraphMapping { // swiftlint:disable:this type_body_length
    private static let modulemapFileSetting = "MODULEMAP_FILE"
    private static let otherCFlagsSetting = "OTHER_CFLAGS"
    private static let otherLinkerFlagsSetting = "OTHER_LDFLAGS"
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
    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
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
            project.targets = project.targets.map { target in
                var target = target
                let targetID = TargetID(projectPath: project.path, targetName: target.name)
                var mappedSettingsDictionary = target.settings?.base ?? [:]
                let hasModuleMap = mappedSettingsDictionary[Self.modulemapFileSetting] != nil
                guard hasModuleMap || !(targetToDependenciesMetadata[targetID]?.isEmpty ?? true) else { return target }

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

                if let updatedOtherLinkerFlags = Self.updatedOtherLinkerFlags(
                    targetID: targetID,
                    oldOtherLinkerFlags: mappedSettingsDictionary[Self.otherLinkerFlagsSetting],
                    targetToDependenciesMetadata: targetToDependenciesMetadata
                ) {
                    mappedSettingsDictionary[Self.otherLinkerFlagsSetting] = updatedOtherLinkerFlags
                }

                let targetSettings = target.settings ?? Settings(
                    base: [:],
                    configurations: [:],
                    defaultSettings: project.settings.defaultSettings
                )
                target.settings = targetSettings.with(base: mappedSettingsDictionary)

                graph.targets[project.path]?[target.name] = target

                return target
            }

            return (projectPath, project)
        })
        return (graph, [])
    } // swiftlint:enable function_body_length

    private static func makeProjectsByPathWithTargetsByName(workspace: WorkspaceWithProjects)
        -> ([AbsolutePath: Project], [String: Target])
    {
        var projectsByPath = [AbsolutePath: Project]()
        var targetsByName = [String: Target]()
        for project in workspace.projects {
            projectsByPath[project.path] = project
            for target in project.targets {
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
        for dependency in target.target.dependencies {
            let dependentProject: Project
            let dependentTarget: GraphTarget
            switch dependency {
            case let .target(name, _):
                guard let dependentTargetFromName = graphTraverser.target(path: target.path, name: name) else {
                    throw ModuleMapMapperError.invalidTargetDependency(
                        sourceProject: target.project.path,
                        sourceTarget: target.target.name,
                        dependentTarget: name
                    )
                }
                dependentProject = target.project
                dependentTarget = dependentTargetFromName
            case let .project(name, path, _):
                guard let dependentProjectFromPath = graph.projects[path],
                      let dependentTargetFromName = graphTraverser.target(path: path, name: name)
                else {
                    throw ModuleMapMapperError.invalidProjectTargetDependency(
                        sourceProject: target.project.path,
                        sourceTarget: target.target.name,
                        dependentProject: path,
                        dependentTarget: name
                    )
                }
                dependentProject = dependentProjectFromPath
                dependentTarget = dependentTargetFromName
            case .framework, .xcframework, .library, .package, .sdk, .xctest:
                continue
            }

            try Self.dependenciesModuleMaps(
                graph: graph,
                target: dependentTarget,
                targetToDependenciesMetadata: &targetToDependenciesMetadata
            )

            // direct dependency module map
            let dependencyModuleMapPath: AbsolutePath?

            if case let .string(dependencyModuleMap) = dependentTarget.target.settings?.base[Self.modulemapFileSetting] {
                let pathString = dependentProject.path.pathString
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
            switch dependentTarget.target.settings?.base[Self.headerSearchPaths] ?? .array([]) {
            case let .array(values):
                headerSearchPaths = values
            case let .string(value):
                headerSearchPaths = [value]
            }

            headerSearchPaths = headerSearchPaths.map {
                let pathString = dependentProject.path.pathString
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
            let dependentTargetID = TargetID(projectPath: dependentProject.path, targetName: dependentTarget.target.name)
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

    private static func updatedOtherLinkerFlags(
        targetID: TargetID,
        oldOtherLinkerFlags: SettingsDictionary.Value?,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>]
    ) -> SettingsDictionary.Value? {
        guard let dependenciesModuleMaps = targetToDependenciesMetadata[targetID]?.compactMap(\.moduleMapPath),
              !dependenciesModuleMaps.isEmpty
        else { return nil }

        var mappedOtherLinkerFlags: [String]
        switch oldOtherLinkerFlags ?? .array(["$(inherited)"]) {
        case let .array(values):
            mappedOtherLinkerFlags = values
        case let .string(value):
            mappedOtherLinkerFlags = value.split(separator: " ").map(String.init)
        }

        if !mappedOtherLinkerFlags.contains("-ObjC") {
            mappedOtherLinkerFlags.append("-ObjC")
        }

        return .array(mappedOtherLinkerFlags)
    }
}
