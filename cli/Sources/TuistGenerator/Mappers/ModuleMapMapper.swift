import Foundation
import Path
import TuistConstants
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

/// Mapper that maps the `MODULE_MAP` build setting to the `-fmodule-map-file` compiler flags.
/// It is required to avoid embedding the module map into the frameworks during cache operations, which would make the framework
/// not portable, as the modulemap could contain absolute paths.
public struct ModuleMapMapper: GraphMapping { // swiftlint:disable:this type_body_length
    private static let modulemapFileSetting = "MODULEMAP_FILE"
    private static let otherCFlagsSetting = "OTHER_CFLAGS"
    private static let otherSwiftFlagsSetting = "OTHER_SWIFT_FLAGS"
    private static let headerSearchPaths = "HEADER_SEARCH_PATHS"
    /// Project-scope user-defined setting that resolves to the absolute path of the SwiftPM `tuist-derived/` directory.
    /// Used to anchor `-fmodule-map-file=` and header-search-path flags so they do not need `..` segments that
    /// can resolve through `.build/checkouts` symlinks (e.g. Namespace's `nscloud-cache-action`). See
    /// `SettingsContentHasher` for the matching hash-time filter that keeps the absolute value out of cache keys.
    static let depsDerivedDirSetting = "TUIST_SPM_DERIVED_DIR"

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
        Logger.current
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
            let depsDerivedRoot = Self.depsDerivedRoot(for: project)
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

                mappedSettingsDictionary = applyModuleMapFlags(
                    to: mappedSettingsDictionary,
                    targetID: targetID,
                    targetToDependenciesMetadata: targetToDependenciesMetadata,
                    depsDerivedRoot: depsDerivedRoot
                )

                if let depsDerivedRoot {
                    mappedSettingsDictionary[Self.depsDerivedDirSetting] = .string(depsDerivedRoot.pathString)
                }

                let targetSettings = target.settings ?? Settings(
                    base: [:],
                    configurations: [:],
                    defaultSettings: project.settings.defaultSettings
                )

                let updatedConfigurations: [BuildConfiguration: Configuration?] = Dictionary(
                    uniqueKeysWithValues: targetSettings.configurations.map { buildConfig, configuration in
                        let configSettings = applyModuleMapFlags(
                            to: configuration?.settings ?? [:],
                            targetID: targetID,
                            targetToDependenciesMetadata: targetToDependenciesMetadata,
                            depsDerivedRoot: depsDerivedRoot,
                            onlyExistingKeys: true
                        )
                        return (
                            buildConfig,
                            configuration?.with(settings: configSettings)
                                ?? Configuration(settings: configSettings)
                        )
                    }
                )

                target.settings = Settings(
                    base: mappedSettingsDictionary,
                    baseDebug: targetSettings.baseDebug,
                    configurations: updatedConfigurations,
                    defaultSettings: targetSettings.defaultSettings,
                    defaultConfiguration: targetSettings.defaultConfiguration
                )

                return (target.name, target)
            })

            return (projectPath, project)
        })
        return (graph, [], environment)
    } // swiftlint:enable function_body_length

    /// Absolute path to the SwiftPM `tuist-derived/` directory for an external SPM-generated project, or `nil` for
    /// local projects. Used to anchor module-map and header search paths on `$(TUIST_SPM_DERIVED_DIR)` rather than on
    /// `$(SRCROOT)` with `..` segments that would traverse the SwiftPM `checkouts/` directory — a directory that some
    /// CI caches (notably Namespace's `nscloud-cache-action`) replace with a symlink, which Xcode 26.5+ resolves
    /// before opening the modulemap and therefore can no longer find it.
    private static func depsDerivedRoot(for project: Project) -> AbsolutePath? {
        guard case .external = project.type,
              let scratch = project.swiftPackageManagerScratchDirectory
        else { return nil }
        return scratch.appending(component: Constants.DerivedDirectory.dependenciesDerivedDirectory)
    }

    /// Returns the flag value to emit for `path`. If `path` lives under `depsDerivedRoot` the result is anchored on
    /// `$(TUIST_SPM_DERIVED_DIR)` (no `..` segments, symlink-safe); otherwise it falls back to the historical
    /// `$(SRCROOT)/<relative>` form so behaviour outside `tuist-derived/` is unchanged.
    private static func referenceString(
        for path: AbsolutePath,
        relativeTo projectPath: AbsolutePath,
        depsDerivedRoot: AbsolutePath?
    ) -> String {
        if let depsDerivedRoot, path.pathString.hasPrefix(depsDerivedRoot.pathString + "/") {
            return "$(\(depsDerivedDirSetting))/\(path.relative(to: depsDerivedRoot).pathString)"
        }
        return "$(SRCROOT)/\(path.relative(to: projectPath).pathString)"
    }

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

    // We apply module map flags to both the base settings and per-configuration overrides.
    // Base settings alone are not enough because Xcode resolves configuration-level keys
    // independently: if a configuration already defines e.g. OTHER_SWIFT_FLAGS, it shadows
    // the base value entirely, so the module map flags would be lost. When updating
    // configuration settings we pass onlyExistingKeys: true so we only patch keys the
    // configuration explicitly overrides, avoiding unnecessary duplication.
    private func applyModuleMapFlags(
        to settings: SettingsDictionary,
        targetID: TargetID,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>],
        depsDerivedRoot: AbsolutePath?,
        onlyExistingKeys: Bool = false
    ) -> SettingsDictionary {
        var settings = settings

        if !onlyExistingKeys || settings[Self.otherSwiftFlagsSetting] != nil,
           let updated = Self.updatedOtherSwiftFlags(
               targetID: targetID,
               oldOtherSwiftFlags: settings[Self.otherSwiftFlagsSetting],
               targetToDependenciesMetadata: targetToDependenciesMetadata,
               depsDerivedRoot: depsDerivedRoot
           )
        {
            settings[Self.otherSwiftFlagsSetting] = updated
        }

        if !onlyExistingKeys || settings[Self.otherCFlagsSetting] != nil,
           let updated = Self.updatedOtherCFlags(
               targetID: targetID,
               oldOtherCFlags: settings[Self.otherCFlagsSetting],
               targetToDependenciesMetadata: targetToDependenciesMetadata,
               depsDerivedRoot: depsDerivedRoot
           )
        {
            settings[Self.otherCFlagsSetting] = updated
        }

        if !onlyExistingKeys || settings[Self.headerSearchPaths] != nil,
           let updated = Self.updatedHeaderSearchPaths(
               targetID: targetID,
               oldHeaderSearchPaths: settings[Self.headerSearchPaths],
               targetToDependenciesMetadata: targetToDependenciesMetadata,
               depsDerivedRoot: depsDerivedRoot
           )
        {
            settings[Self.headerSearchPaths] = updated
        }

        return settings
    }

    private static func updatedHeaderSearchPaths(
        targetID: TargetID,
        oldHeaderSearchPaths: SettingsDictionary.Value?,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>],
        depsDerivedRoot: AbsolutePath?
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
            if let absolute = try? AbsolutePath(validating: headerSearchPath) {
                mappedHeaderSearchPaths.append(
                    referenceString(
                        for: absolute,
                        relativeTo: targetID.projectPath,
                        depsDerivedRoot: depsDerivedRoot
                    )
                )
            } else {
                mappedHeaderSearchPaths.append(headerSearchPath)
            }
        }

        return .array(mappedHeaderSearchPaths)
    }

    private static func updatedOtherSwiftFlags(
        targetID: TargetID,
        oldOtherSwiftFlags: SettingsDictionary.Value?,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>],
        depsDerivedRoot: AbsolutePath?
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
            let reference = referenceString(
                for: moduleMap,
                relativeTo: targetID.projectPath,
                depsDerivedRoot: depsDerivedRoot
            )
            mappedOtherSwiftFlags.append(contentsOf: [
                "-Xcc",
                "-fmodule-map-file=\(reference)",
            ])
        }

        return .array(mappedOtherSwiftFlags)
    }

    private static func updatedOtherCFlags(
        targetID: TargetID,
        oldOtherCFlags: SettingsDictionary.Value?,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>],
        depsDerivedRoot: AbsolutePath?
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
            let reference = referenceString(
                for: moduleMap,
                relativeTo: targetID.projectPath,
                depsDerivedRoot: depsDerivedRoot
            )
            mappedOtherCFlags.append("-fmodule-map-file=\(reference)")
        }

        return .array(mappedOtherCFlags)
    }
}
