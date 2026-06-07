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
///
/// To avoid "Argument list too long" errors for targets with many transitive dependencies, this mapper generates a single
/// combined module map file per target using `extern module` declarations, rather than adding individual
/// `-fmodule-map-file` flags for each dependency.
///
/// This mirrors SwiftPM's package PIF builder, which propagates custom and generated module maps to clients
/// with `-fmodule-map-file`:
/// https://github.com/swiftlang/swift-package-manager/blob/ff05594c1267137ed5ee2c0076dfaf78f0289877/Sources/SwiftBuildSupport/PackagePIFProjectBuilder%2BModules.swift#L440-L459
public struct ModuleMapMapper: GraphMapping { // swiftlint:disable:this type_body_length
    private static let modulemapFileSetting = "MODULEMAP_FILE"
    private static let otherCFlagsSetting = "OTHER_CFLAGS"
    private static let otherSwiftFlagsSetting = "OTHER_SWIFT_FLAGS"
    private static let headerSearchPaths = "HEADER_SEARCH_PATHS"

    private struct TargetID: Hashable {
        let projectPath: AbsolutePath
        let targetName: String
    }

    private struct DependencyMetadata: Hashable {
        let moduleName: String
        let moduleMapPath: AbsolutePath?
        let headerSearchPaths: [String]
    }

    private struct DependenciesModuleMapsFrame {
        let targetID: TargetID
        let dependencies: [GraphTargetReference]
        var nextDependencyIndex: Int
        var dependenciesMetadata: Set<DependencyMetadata>
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
                graphTraverser: graphTraverser,
                target: target,
                targetToDependenciesMetadata: &targetToDependenciesMetadata
            )
        }

        var graph = graph
        var sideEffects: [SideEffectDescriptor] = []

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            let derivedDirectory = dependenciesDerivedDirectory(for: project)
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { targetName, target in
                var target = target
                let targetID = TargetID(projectPath: project.path, targetName: target.name)
                var mappedSettingsDictionary = target.settings?.base ?? [:]
                let hasModuleMap = mappedSettingsDictionary[Self.modulemapFileSetting] != nil
                guard hasModuleMap || !(targetToDependenciesMetadata[targetID]?.isEmpty ?? true)
                else { return (targetName, target) }

                if hasModuleMap {
                    if let moduleMapPath = Self.moduleMapPath(
                        from: mappedSettingsDictionary[Self.modulemapFileSetting],
                        projectPath: project.path
                    ),
                        target.product.isFramework
                    {
                        // swift-build gives ExtractAPI dependency module maps explicitly and models framework module maps
                        // at `Modules/module.modulemap`. Generated Xcode projects need the same canonical framework path.
                        // https://github.com/swiftlang/swift-build/blob/af813e185ed298ea7bdb633047f27d15253cdac7/Sources/SWBTaskConstruction/TaskProducers/OtherTaskProducers/TAPISymbolExtractorTaskProducer.swift#L76-L108
                        // https://github.com/swiftlang/swift-build/blob/af813e185ed298ea7bdb633047f27d15253cdac7/Sources/SWBTaskConstruction/ProductPlanning/ProductPlan.swift#L1197-L1200
                        target.scripts.append(
                            TargetScript(
                                name: "Copy Module Map",
                                order: .post,
                                script: .embedded(
                                    """
                                    set -eu
                                    mkdir -p "$TARGET_BUILD_DIR/$WRAPPER_NAME/Modules"
                                    cp '\(Self.shellEscaped(moduleMapPath.pathString))' "$TARGET_BUILD_DIR/$WRAPPER_NAME/Modules/module.modulemap"
                                    """
                                ),
                                inputPaths: [moduleMapPath.pathString],
                                outputPaths: ["$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/Modules/module.modulemap"],
                                showEnvVarsInLog: false,
                                basedOnDependencyAnalysis: true
                            )
                        )
                    }
                    mappedSettingsDictionary[Self.modulemapFileSetting] = nil
                }

                let combinedModuleMap = Self.combinedModuleMapContent(
                    targetID: targetID,
                    project: project,
                    targetToDependenciesMetadata: targetToDependenciesMetadata
                )

                if let combinedModuleMap {
                    sideEffects.append(
                        .file(FileDescriptor(
                            path: combinedModuleMap.path,
                            contents: combinedModuleMap.content
                        ))
                    )
                }

                mappedSettingsDictionary = applyModuleMapFlags(
                    to: mappedSettingsDictionary,
                    targetID: targetID,
                    targetToDependenciesMetadata: targetToDependenciesMetadata,
                    dependenciesDerivedDirectory: derivedDirectory,
                    xcodeProjParent: project.xcodeProjPath.parentDirectory,
                    combinedModuleMapPath: combinedModuleMap?.path
                )

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
                            dependenciesDerivedDirectory: derivedDirectory,
                            xcodeProjParent: project.xcodeProjPath.parentDirectory,
                            combinedModuleMapPath: combinedModuleMap?.path,
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
        return (graph, sideEffects, environment)
    } // swiftlint:enable function_body_length

    private static func moduleMapPath(
        from value: SettingsDictionary.Value?,
        projectPath: AbsolutePath
    ) -> AbsolutePath? {
        guard case let .string(moduleMap) = value else { return nil }

        return try? AbsolutePath(
            validating: moduleMap
                .replacingOccurrences(of: "$(PROJECT_DIR)", with: projectPath.pathString)
                .replacingOccurrences(of: "$(SRCROOT)", with: projectPath.pathString)
                .replacingOccurrences(of: "$(SOURCE_ROOT)", with: projectPath.pathString)
        )
    }

    private static func shellEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    /// The `tuist-derived/` directory for an external SPM-generated project, or `nil` for local projects.
    /// Used as a gating condition for `referenceString` to decide whether a referenced path is one Tuist owns
    /// and should anchor on `$(PROJECT_DIR)` instead of `$(SRCROOT)`.
    private func dependenciesDerivedDirectory(for project: Project) -> AbsolutePath? {
        guard case .external = project.type,
              let scratch = project.swiftPackageManagerScratchDirectory
        else { return nil }
        return scratch.appending(component: Constants.DerivedDirectory.dependenciesDerivedDirectory)
    }

    /// Returns the flag value to emit for `path`. Paths under `dependenciesDerivedDirectory` anchor on
    /// `$(PROJECT_DIR)` so the substituted absolute path stays inside `tuist-derived/` and never traverses the
    /// SwiftPM `checkouts/` symlink (see the file-level header for the underlying Xcode 26.5 dep-scanner
    /// behaviour this avoids). All other paths keep the historical `$(SRCROOT)/<rel>` form.
    private static func referenceString(
        for path: AbsolutePath,
        relativeTo projectPath: AbsolutePath,
        dependenciesDerivedDirectory: AbsolutePath?,
        xcodeProjParent: AbsolutePath
    ) -> String {
        if let dependenciesDerivedDirectory, path.pathString.hasPrefix(dependenciesDerivedDirectory.pathString + "/") {
            return "$(PROJECT_DIR)/\(path.relative(to: xcodeProjParent).pathString)"
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
        graphTraverser: GraphTraverser,
        target: GraphTarget,
        targetToDependenciesMetadata: inout [TargetID: Set<DependencyMetadata>]
    ) throws {
        let targetID = Self.targetID(target)
        if targetToDependenciesMetadata[targetID] != nil {
            // already computed
            return
        }

        var activeTargetIDs = Set<TargetID>()
        var stack = [
            DependenciesModuleMapsFrame(
                targetID: targetID,
                dependencies: Self.directTargetDependencies(graphTraverser: graphTraverser, target: target),
                nextDependencyIndex: 0,
                dependenciesMetadata: []
            ),
        ]
        activeTargetIDs.insert(targetID)

        while let frame = stack.last {
            let frameIndex = stack.count - 1
            if frame.nextDependencyIndex < frame.dependencies.count {
                let dependency = frame.dependencies[frame.nextDependencyIndex]
                let dependencyTargetID = Self.targetID(dependency.graphTarget)

                if let indirectDependencyMetadata = targetToDependenciesMetadata[dependencyTargetID] {
                    stack[frameIndex].nextDependencyIndex += 1
                    stack[frameIndex].dependenciesMetadata.formUnion(indirectDependencyMetadata)
                    stack[frameIndex].dependenciesMetadata.insert(
                        try Self.dependencyMetadata(for: dependency)
                    )
                    continue
                }

                if activeTargetIDs.contains(dependencyTargetID) {
                    throw GraphAlgorithmError.unexpectedCycle
                }

                activeTargetIDs.insert(dependencyTargetID)
                stack.append(
                    DependenciesModuleMapsFrame(
                        targetID: dependencyTargetID,
                        dependencies: Self.directTargetDependencies(
                            graphTraverser: graphTraverser,
                            target: dependency.graphTarget
                        ),
                        nextDependencyIndex: 0,
                        dependenciesMetadata: []
                    )
                )
            } else {
                let completedFrame = stack.removeLast()
                targetToDependenciesMetadata[completedFrame.targetID] = completedFrame.dependenciesMetadata
                activeTargetIDs.remove(completedFrame.targetID)
            }
        }
    }

    private static func targetID(_ target: GraphTarget) -> TargetID {
        TargetID(projectPath: target.path, targetName: target.target.name)
    }

    private static func directTargetDependencies(
        graphTraverser: GraphTraverser,
        target: GraphTarget
    ) -> [GraphTargetReference] {
        Array(
            graphTraverser.directTargetDependencies(
                path: target.path,
                name: target.target.name
            )
        )
    }

    private static func dependencyMetadata(for dependency: GraphTargetReference) throws -> DependencyMetadata {
        let dependencyModuleMapPath: AbsolutePath?
        let pathString = dependency.graphTarget.path.pathString

        if case let .string(dependencyModuleMap) = dependency.target.settings?.base[Self.modulemapFileSetting] {
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
        switch dependency.target.settings?.base[Self.headerSearchPaths] ?? .array([]) {
        case let .array(values):
            headerSearchPaths = values
        case let .string(value):
            headerSearchPaths = [value]
        }

        return DependencyMetadata(
            moduleName: dependency.target.productName,
            moduleMapPath: dependencyModuleMapPath,
            headerSearchPaths: headerSearchPaths.map {
                (
                    try? AbsolutePath(
                        validating: $0
                            .replacingOccurrences(of: "$(PROJECT_DIR)", with: pathString)
                            .replacingOccurrences(of: "$(SRCROOT)", with: pathString)
                            .replacingOccurrences(of: "$(SOURCE_ROOT)", with: pathString)
                    ).pathString
                ) ?? $0
            }
        )
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
        dependenciesDerivedDirectory: AbsolutePath?,
        xcodeProjParent: AbsolutePath,
        combinedModuleMapPath: AbsolutePath?,
        onlyExistingKeys: Bool = false
    ) -> SettingsDictionary {
        var settings = settings

        if !onlyExistingKeys || settings[Self.otherSwiftFlagsSetting] != nil,
           let updated = Self.updatedOtherSwiftFlags(
               targetID: targetID,
               oldOtherSwiftFlags: settings[Self.otherSwiftFlagsSetting],
               dependenciesDerivedDirectory: dependenciesDerivedDirectory,
               xcodeProjParent: xcodeProjParent,
               combinedModuleMapPath: combinedModuleMapPath
           )
        {
            settings[Self.otherSwiftFlagsSetting] = updated
        }

        if !onlyExistingKeys || settings[Self.otherCFlagsSetting] != nil,
           let updated = Self.updatedOtherCFlags(
               targetID: targetID,
               oldOtherCFlags: settings[Self.otherCFlagsSetting],
               dependenciesDerivedDirectory: dependenciesDerivedDirectory,
               xcodeProjParent: xcodeProjParent,
               combinedModuleMapPath: combinedModuleMapPath
           )
        {
            settings[Self.otherCFlagsSetting] = updated
        }

        if !onlyExistingKeys || settings[Self.headerSearchPaths] != nil,
           let updated = Self.updatedHeaderSearchPaths(
               targetID: targetID,
               oldHeaderSearchPaths: settings[Self.headerSearchPaths],
               targetToDependenciesMetadata: targetToDependenciesMetadata,
               dependenciesDerivedDirectory: dependenciesDerivedDirectory,
               xcodeProjParent: xcodeProjParent
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
        dependenciesDerivedDirectory: AbsolutePath?,
        xcodeProjParent: AbsolutePath
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
                        dependenciesDerivedDirectory: dependenciesDerivedDirectory,
                        xcodeProjParent: xcodeProjParent
                    )
                )
            } else {
                mappedHeaderSearchPaths.append(headerSearchPath)
            }
        }

        return .array(mappedHeaderSearchPaths)
    }

    private static func combinedModuleMapContent(
        targetID: TargetID,
        project: Project,
        targetToDependenciesMetadata: [TargetID: Set<DependencyMetadata>]
    ) -> (path: AbsolutePath, content: Data)? {
        guard let dependenciesMetadata = targetToDependenciesMetadata[targetID] else { return nil }

        let moduleMapsMetadata = dependenciesMetadata
            .filter { $0.moduleMapPath != nil }
            .sorted { $0.moduleName < $1.moduleName }

        guard !moduleMapsMetadata.isEmpty else { return nil }

        let content = moduleMapsMetadata
            .map { "extern module \($0.moduleName) \"\($0.moduleMapPath!.pathString)\"" }
            .joined(separator: "\n")
            + "\n"

        let combinedPath: AbsolutePath
        if case .external = project.type,
           let scratch = project.swiftPackageManagerScratchDirectory
        {
            combinedPath = scratch.appending(
                components: Constants.DerivedDirectory.dependenciesDerivedDirectory,
                Constants.DerivedDirectory.dependenciesModuleMapsDirectory,
                project.name.sanitizedModuleName,
                "\(targetID.targetName)-deps.modulemap"
            )
        } else {
            combinedPath = targetID.projectPath.appending(
                components: Constants.DerivedDirectory.name,
                Constants.DerivedDirectory.moduleMaps,
                "\(targetID.targetName)-deps.modulemap"
            )
        }

        return (path: combinedPath, content: Data(content.utf8))
    }

    private static func updatedOtherSwiftFlags(
        targetID: TargetID,
        oldOtherSwiftFlags: SettingsDictionary.Value?,
        dependenciesDerivedDirectory: AbsolutePath?,
        xcodeProjParent: AbsolutePath,
        combinedModuleMapPath: AbsolutePath?
    ) -> SettingsDictionary.Value? {
        guard let combinedModuleMapPath else { return nil }

        var mappedOtherSwiftFlags: [String]
        switch oldOtherSwiftFlags ?? .array(["$(inherited)"]) {
        case let .array(values):
            mappedOtherSwiftFlags = values
        case let .string(value):
            mappedOtherSwiftFlags = value.split(separator: " ").map(String.init)
        }

        let reference = referenceString(
            for: combinedModuleMapPath,
            relativeTo: targetID.projectPath,
            dependenciesDerivedDirectory: dependenciesDerivedDirectory,
            xcodeProjParent: xcodeProjParent
        )
        mappedOtherSwiftFlags.append(contentsOf: [
            "-Xcc",
            "-fmodule-map-file=\"\(reference)\"",
        ])

        return .array(mappedOtherSwiftFlags)
    }

    private static func updatedOtherCFlags(
        targetID: TargetID,
        oldOtherCFlags: SettingsDictionary.Value?,
        dependenciesDerivedDirectory: AbsolutePath?,
        xcodeProjParent: AbsolutePath,
        combinedModuleMapPath: AbsolutePath?
    ) -> SettingsDictionary.Value? {
        guard let combinedModuleMapPath else { return nil }

        var mappedOtherCFlags: [String]
        switch oldOtherCFlags ?? .array(["$(inherited)"]) {
        case let .array(values):
            mappedOtherCFlags = values
        case let .string(value):
            mappedOtherCFlags = value.split(separator: " ").map(String.init)
        }

        let reference = referenceString(
            for: combinedModuleMapPath,
            relativeTo: targetID.projectPath,
            dependenciesDerivedDirectory: dependenciesDerivedDirectory,
            xcodeProjParent: xcodeProjParent
        )
        mappedOtherCFlags.append(
            "-fmodule-map-file=\"\(reference)\""
        )

        return .array(mappedOtherCFlags)
    }
}
