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
/// not portable, as
/// the modulemap could contain absolute paths.
public final class ModuleMapMapper: WorkspaceMapping {
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
    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        logger
            .debug(
                "Transforming workspace \(workspace.workspace.name): Mapping MODULE_MAP build setting to -fmodule-map-file compiler flag"
            )

        let (projectsByPath, targetsByName) = Self.makeProjectsByPathWithTargetsByName(workspace: workspace)
        var targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>] = [:]
        for project in workspace.projects {
            for target in project.targets {
                try Self.dependenciesModuleMaps(
                    workspace: workspace,
                    project: project,
                    target: target,
                    targetToDependenciesMetadata: &targetToDependenciesMetadata,
                    projectsByPath: projectsByPath,
                    targetsByName: targetsByName
                )
            }
        }

        var mappedWorkspace = workspace
        for projectIndex in 0 ..< workspace.projects.count {
            var mappedProject = workspace.projects[projectIndex]
            for targetIndex in 0 ..< mappedProject.targets.count {
                var mappedTarget = mappedProject.targets[targetIndex]
                let targetID = TargetID(projectPath: mappedProject.path, targetName: mappedTarget.name)
                var mappedSettingsDictionary = mappedTarget.settings?.base ?? [:]
                let hasModuleMap = mappedSettingsDictionary[Self.modulemapFileSetting] != nil
                guard hasModuleMap || !(targetToDependenciesMetadata[targetID]?.isEmpty ?? true) else { continue }

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

                let targetSettings = mappedTarget.settings ?? Settings(
                    base: [:],
                    configurations: [:],
                    defaultSettings: mappedProject.settings.defaultSettings
                )
                mappedTarget.settings = targetSettings.with(base: mappedSettingsDictionary)
                mappedProject.targets[targetIndex] = mappedTarget
            }
            mappedWorkspace.projects[projectIndex] = mappedProject
        }
        return (mappedWorkspace, [])
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

    /// Calculates the set of module maps to be linked to a given target and populates the `targetToDependenciesMetadata` dictionary.
    /// Each target must link the module map of its direct and indirect dependencies.
    /// The `targetToDependenciesMetadata` is also used as cache to avoid recomputing the set for already computed targets.
    private static func dependenciesModuleMaps( // swiftlint:disable:this function_body_length
        workspace: WorkspaceWithProjects,
        project: Project,
        target: Target,
        targetToDependenciesMetadata: inout [TargetID: Set<DependencyMetadata>],
        projectsByPath: [AbsolutePath: Project],
        targetsByName: [String: Target]
    ) throws {
        let targetID = TargetID(projectPath: project.path, targetName: target.name)
        if targetToDependenciesMetadata[targetID] != nil {
            // already computed
            return
        }

        var dependenciesMetadata: Set<DependencyMetadata> = []
        for dependency in target.dependencies {
            let dependentProject: Project
            let dependentTarget: Target
            switch dependency {
            case let .target(name, _):
                guard let dependentTargetFromName = targetsByName[name] else {
                    throw ModuleMapMapperError.invalidTargetDependency(
                        sourceProject: project.path,
                        sourceTarget: target.name,
                        dependentTarget: name
                    )
                }
                dependentProject = project
                dependentTarget = dependentTargetFromName
            case let .project(name, path, _):
                guard let dependentProjectFromPath = projectsByPath[path],
                      let dependentTargetFromName = targetsByName[name]
                else {
                    throw ModuleMapMapperError.invalidProjectTargetDependency(
                        sourceProject: project.path,
                        sourceTarget: target.name,
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
                workspace: workspace,
                project: dependentProject,
                target: dependentTarget,
                targetToDependenciesMetadata: &targetToDependenciesMetadata,
                projectsByPath: projectsByPath,
                targetsByName: targetsByName
            )

            // direct dependency module map
            let dependencyModuleMapPath: AbsolutePath?
            
            if case let .string(dependencyModuleMap) = dependentTarget.settings?.base[Self.modulemapFileSetting] {
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
            
            
            let headerSearchPaths: [String]
            switch dependentTarget.settings?.base[Self.headerSearchPaths] ?? .array([]) {
            case let .array(values):
                headerSearchPaths = values
            case let .string(values):
                headerSearchPaths = [values]
            }

            // indirect dependency module maps
            let dependentTargetID = TargetID(projectPath: dependentProject.path, targetName: dependentTarget.name)
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
        guard
            !dependenciesHeaderSearchPaths.isEmpty 
        else { return nil }

        var mappedHeaderSearchPaths: [String]
        switch oldHeaderSearchPaths ?? .array(["$(inherited)"]) {
        case let .array(values):
            mappedHeaderSearchPaths = values
        case let .string(value):
            mappedHeaderSearchPaths = value.split(separator: " ").map(String.init)
        }

        for headerSearchPaths in dependenciesHeaderSearchPaths.sorted() {
            mappedHeaderSearchPaths.append(
                headerSearchPaths
            )
        }

        return .array(mappedHeaderSearchPaths)
    }

    private static func updatedOtherSwiftFlags(
        targetID: TargetID,
        oldOtherSwiftFlags: SettingsDictionary.Value?,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>]
    ) -> SettingsDictionary.Value? {
        guard
            let dependenciesModuleMaps = targetToDependenciesMetadata[targetID]?.compactMap(\.moduleMapPath),
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
        guard
            let dependenciesModuleMaps = targetToDependenciesMetadata[targetID]?.compactMap(\.moduleMapPath),
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
        guard
            let dependenciesModuleMaps = targetToDependenciesMetadata[targetID]?.compactMap(\.moduleMapPath),
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
