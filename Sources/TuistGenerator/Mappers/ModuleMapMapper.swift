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

    public init() {}

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var targetToModuleMaps: [TargetID: Set<AbsolutePath>] = [:]
        workspace.projects.forEach { project in
            project.targets.forEach { target in
                Self.dependenciesModuleMaps(workspace: workspace, project: project, target: target, targetToModuleMaps: &targetToModuleMaps)
            }
        }

        var mappedWorkspace = workspace
        for p in 0 ..< workspace.projects.count {
            var mappedProject = workspace.projects[p]
            for t in 0 ..< mappedProject.targets.count {
                var mappedTarget = mappedProject.targets[t]
                let targetID = TargetID(projectPath: mappedProject.path, targetName: mappedTarget.name)
                var mappedSettingsDictionary = mappedTarget.settings?.base ?? [:]
                guard mappedSettingsDictionary[Self.modulemapFileSetting] != nil || targetToModuleMaps[targetID] != nil else { continue }

                if mappedSettingsDictionary[Self.modulemapFileSetting] != nil {
                    mappedSettingsDictionary[Self.modulemapFileSetting] = nil
                }

                if let dependenciesModuleMaps = targetToModuleMaps[targetID] {
                    var mappedSwiftCompilerFlags: [String]
                    switch mappedSettingsDictionary[Self.otherSwiftFlagsSetting, default: .array(["$(inherited)"])] {
                    case .array(let values):
                        mappedSwiftCompilerFlags = values
                    case .string(let value):
                        mappedSwiftCompilerFlags = value.split(separator: " ").map(String.init)
                    }

                    for moduleMap in dependenciesModuleMaps.sorted() {
                        mappedSwiftCompilerFlags.append(contentsOf: [
                            "-Xcc",
                            "-fmodule-map-file=$(SRCROOT)/\(moduleMap.relative(to: mappedProject.path))"
                        ])
                    }
                    mappedSettingsDictionary[Self.otherSwiftFlagsSetting] = .array(mappedSwiftCompilerFlags)
                }

                mappedTarget.settings = (mappedTarget.settings ?? .default).with(base: mappedSettingsDictionary)
                mappedProject.targets[t] = mappedTarget
            }
            mappedWorkspace.projects[p] = mappedProject
        }
        return (mappedWorkspace, [])
    }

    fileprivate static func dependenciesModuleMaps(
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

    fileprivate struct TargetID: Hashable {
        let projectPath: AbsolutePath
        let targetName: String
    }
}
