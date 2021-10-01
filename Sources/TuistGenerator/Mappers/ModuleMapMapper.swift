import Foundation
import TuistCore
import TuistGraph
import TSCBasic

/// Mapper that maps the `MODULE_MAP` build setting to the `-fmodule-map-file` compiler flags.
/// It is required to avoid embedding the module map into the frameworks during cache operations, which would make the framework not portable, as
/// the modulemap could contain absolute paths.
public final class ModuleMapMapper: WorkspaceMapping {
    private static let modulemapFileSetting = "MODULEMAP_FILE"
    private static let otherSwiftFlagsSetting = "OTHER_SWIFT_FLAGS"

    private struct TargetID: Hashable {
        let projectPath: AbsolutePath
        let targetName: String
    }

    public init() {}

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var targetToModuleMaps: [TargetID: Set<AbsolutePath>] = [:]
        workspace.projects.forEach { project in
            project.targets.forEach { target in
                Self.dependenciesModuleMaps(workspace: workspace, project: project, target: target, targetToModuleMaps: &targetToModuleMaps)
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
                guard hasModuleMap || targetToModuleMaps[targetID] != nil else { continue }

                if hasModuleMap {
                    mappedSettingsDictionary[Self.modulemapFileSetting] = nil
                }

                if let updatedOtherSwiftFlags = Self.updatedOtherSwiftFlags(
                    targetID: targetID,
                    oldOtherSwiftFlags: mappedSettingsDictionary[Self.otherSwiftFlagsSetting],
                    targetToModuleMaps: targetToModuleMaps
                ) {
                    mappedSettingsDictionary[Self.otherSwiftFlagsSetting] = updatedOtherSwiftFlags
                }

                mappedTarget.settings = (mappedTarget.settings ?? .default).with(base: mappedSettingsDictionary)
                mappedProject.targets[targetIndex] = mappedTarget
            }
            mappedWorkspace.projects[projectIndex] = mappedProject
        }
        return (mappedWorkspace, [])
    }

    /// Calculates the set of module maps to be linked to a given target and populates the `targetToModuleMaps` dictionary.
    /// Each target must link the module map of its direct and indirect dependencies.
    /// The `targetToModuleMaps` is also used as cache to avoid recomputing the set for already computed targets.
    private static func dependenciesModuleMaps(
        workspace: WorkspaceWithProjects,
        project: Project,
        target: Target,
        targetToModuleMaps: inout [TargetID: Set<AbsolutePath>]
    ) {
        let targetID = TargetID(projectPath: project.path, targetName: target.name)
        if targetToModuleMaps[targetID] != nil {
            // already computed
            return
        }

        var dependenciesModuleMaps: Set<AbsolutePath> = []
        for dependency in target.dependencies {
            let dependentProject: Project
            let dependentTarget: Target
            switch dependency {
            case .target(let name):
                dependentProject = project
                dependentTarget = project.targets.first(where: { $0.name == name })!
            case .project(let name, let path):
                dependentProject = workspace.projects.first(where: { $0.path == path })!
                dependentTarget = dependentProject.targets.first(where: { $0.name == name })!
            case .framework, .xcframework, .library, .package, .sdk, .cocoapods, .xctest:
                continue
            }

            Self.dependenciesModuleMaps(
                workspace: workspace,
                project: dependentProject,
                target: dependentTarget,
                targetToModuleMaps: &targetToModuleMaps
            )

            // direct dependency module map
            if case let .string(dependencyModuleMap) = dependentTarget.settings?.base[Self.modulemapFileSetting] {
                let dependencyModuleMapPath = AbsolutePath(
                    dependencyModuleMap
                        .replacingOccurrences(of: "$(PROJECT_DIR)", with: dependentProject.path.pathString)
                        .replacingOccurrences(of: "$(SRCROOT)", with: dependentProject.path.pathString)
                        .replacingOccurrences(of: "$(SOURCE_ROOT)", with: dependentProject.path.pathString)
                )
                dependenciesModuleMaps.insert(dependencyModuleMapPath)
            }

            // indirect dependency module maps
            let dependentTargetID = TargetID(projectPath: dependentProject.path, targetName: dependentTarget.name)
            if let indirectDependencyModuleMap = targetToModuleMaps[dependentTargetID] {
                dependenciesModuleMaps.formUnion(indirectDependencyModuleMap)
            }
        }

        if !dependenciesModuleMaps.isEmpty {
            targetToModuleMaps[targetID] = dependenciesModuleMaps
        }
    }

    private static func updatedOtherSwiftFlags(
        targetID: TargetID,
        oldOtherSwiftFlags: SettingsDictionary.Value?,
        targetToModuleMaps: [TargetID: Set<AbsolutePath>]
    ) -> SettingsDictionary.Value? {
        guard let dependenciesModuleMaps = targetToModuleMaps[targetID] else { return nil }

        var mappedSwiftCompilerFlags: [String]
        switch oldOtherSwiftFlags ?? .array(["$(inherited)"]) {
        case .array(let values):
            mappedSwiftCompilerFlags = values
        case .string(let value):
            mappedSwiftCompilerFlags = value.split(separator: " ").map(String.init)
        }

        for moduleMap in dependenciesModuleMaps.sorted() {
            mappedSwiftCompilerFlags.append(contentsOf: [
                "-Xcc",
                "-fmodule-map-file=$(SRCROOT)/\(moduleMap.relative(to: targetID.projectPath))"
            ])
        }

        return .array(mappedSwiftCompilerFlags)
    }
}
