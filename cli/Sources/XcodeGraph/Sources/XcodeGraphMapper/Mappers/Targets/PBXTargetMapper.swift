import FileSystem
import Foundation
import Mockable
import Path
import XcodeGraph
import XcodeProj

/// Errors that may occur while mapping a `PBXTarget` into a domain-level `Target`.
enum PBXTargetMappingError: LocalizedError, Equatable {
    case noProjectsFound(path: String)
    case missingFilesGroup(targetName: String)
    case invalidPlist(path: String)

    var errorDescription: String? {
        switch self {
        case let .noProjectsFound(path):
            return "No project was found at: \(path)."
        case let .missingFilesGroup(targetName):
            return "The files group is missing for the target '\(targetName)'."
        case let .invalidPlist(path):
            return "Failed to read a valid plist dictionary from file at: \(path)."
        }
    }
}

/// A protocol defining how to map a `PBXTarget` into a domain-level `Target` model.
///
/// Conforming types transform raw `PBXTarget` instances—including their build phases,
/// settings, and dependencies—into fully realized `Target` models suitable for analysis,
/// code generation, or tooling integration.
@Mockable
protocol PBXTargetMapping {
    /// Maps a given `PBXTarget` into a `Target` model.
    ///
    /// This involves:
    /// - Extracting platform, product, and deployment information.
    /// - Mapping build phases (sources, resources, headers, scripts, copy files, frameworks, etc.).
    /// - Resolving dependencies (project-based, frameworks, libraries, packages, SDKs).
    /// - Reading settings, launch arguments, and metadata.
    ///
    /// - Parameters:
    ///   - pbxTarget: The `PBXTarget` to map.
    ///   - xcodeProj: Provides access to `.xcodeproj` data and the source directory for path resolution.
    /// - Returns: A fully mapped `Target` model.
    /// - Throws: `PBXTargetMappingError` if required data (like a bundle identifier) is missing,
    ///           or if necessary files/groups cannot be found.
    func map(
        pbxTarget: PBXTarget,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget],
        packages: [AbsolutePath]
    ) async throws -> Target?
}

// swiftlint:disable function_body_length
// swiftlint:disable type_body_length
/// A mapper that converts a `PBXTarget` into a domain `Target` model.
///
/// `PBXTargetMapper` orchestrates various specialized mappers (e.g., sources, resources, headers)
/// and dependency resolvers to produce a comprehensive `Target` suitable for downstream tasks.
struct PBXTargetMapper: PBXTargetMapping {
    private let settingsMapper: SettingsMapping
    private let sourcesMapper: PBXSourcesBuildPhaseMapping
    private let resourcesMapper: PBXResourcesBuildPhaseMapping
    private let headersMapper: PBXHeadersBuildPhaseMapping
    private let scriptsMapper: PBXScriptsBuildPhaseMapping
    private let copyFilesMapper: PBXCopyFilesBuildPhaseMapping
    private let coreDataModelsMapper: PBXCoreDataModelsBuildPhaseMapping
    private let frameworksMapper: PBXFrameworksBuildPhaseMapping
    private let dependencyMapper: PBXTargetDependencyMapping
    private let buildRuleMapper: BuildRuleMapping
    private let fileSystem: FileSysteming

    init(
        settingsMapper: SettingsMapping = XCConfigurationMapper(),
        sourcesMapper: PBXSourcesBuildPhaseMapping = PBXSourcesBuildPhaseMapper(),
        resourcesMapper: PBXResourcesBuildPhaseMapping = PBXResourcesBuildPhaseMapper(),
        headersMapper: PBXHeadersBuildPhaseMapping = PBXHeadersBuildPhaseMapper(),
        scriptsMapper: PBXScriptsBuildPhaseMapping = PBXScriptsBuildPhaseMapper(),
        copyFilesMapper: PBXCopyFilesBuildPhaseMapping = PBXCopyFilesBuildPhaseMapper(),
        coreDataModelsMapper: PBXCoreDataModelsBuildPhaseMapping = PBXCoreDataModelsBuildPhaseMapper(),
        frameworksMapper: PBXFrameworksBuildPhaseMapping = PBXFrameworksBuildPhaseMapper(),
        dependencyMapper: PBXTargetDependencyMapping = PBXTargetDependencyMapper(),
        buildRuleMapper: BuildRuleMapping = PBXBuildRuleMapper(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.settingsMapper = settingsMapper
        self.sourcesMapper = sourcesMapper
        self.resourcesMapper = resourcesMapper
        self.headersMapper = headersMapper
        self.scriptsMapper = scriptsMapper
        self.copyFilesMapper = copyFilesMapper
        self.coreDataModelsMapper = coreDataModelsMapper
        self.frameworksMapper = frameworksMapper
        self.dependencyMapper = dependencyMapper
        self.buildRuleMapper = buildRuleMapper
        self.fileSystem = fileSystem
    }

    func map(
        pbxTarget: PBXTarget,
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget],
        packages: [AbsolutePath]
    ) async throws -> Target? {
        // `XcodeGraph` currently doesn't support representing aggregate targets
        if pbxTarget is PBXAggregateTarget {
            return nil
        }
        let platform = try pbxTarget.platform()
        let deploymentTargets = pbxTarget.deploymentTargets()
        let productType = pbxTarget.productType?.mapProductType()
        let product = try productType.throwing(PlatformInferenceError.noPlatformInferred(pbxTarget.name))

        // Project settings and configurations
        let settings = try settingsMapper.map(
            xcodeProj: xcodeProj,
            configurationList: pbxTarget.buildConfigurationList
        )

        // Build Phases
        var sources = try pbxTarget.sourcesBuildPhase().map {
            try sourcesMapper.map($0, xcodeProj: xcodeProj)
        } ?? []
        sources = try await fileSystemSynchronizedGroupsSources(
            from: pbxTarget,
            xcodeProj: xcodeProj,
            packages: packages
        ) + sources

        var (resources, resourceDependencies) = try pbxTarget.resourcesBuildPhase().map {
            try resourcesMapper.map(
                $0,
                xcodeProj: xcodeProj,
                projectNativeTargets: projectNativeTargets
            )
        } ?? ([], [])
        resources = try await fileSystemSynchronizedGroupsResources(
            from: pbxTarget,
            xcodeProj: xcodeProj
        ) + resources

        var headers = try pbxTarget.headersBuildPhase().map {
            try headersMapper.map($0, xcodeProj: xcodeProj)
        } ?? nil

        headers = try await addHeadersFromFileSystemSynchronizedGroups(
            from: pbxTarget,
            xcodeProj: xcodeProj,
            headers: headers
        )

        let runScriptPhases = pbxTarget.runScriptBuildPhases()
        let scripts = try scriptsMapper.map(runScriptPhases, buildPhases: pbxTarget.buildPhases)
        let rawScriptBuildPhases = scriptsMapper.mapRawScriptBuildPhases(runScriptPhases)

        let copyFilesPhases = pbxTarget.copyFilesBuildPhases()
        let copyFiles = try copyFilesMapper.map(
            copyFilesPhases,
            fileSystemSynchronizedGroups: pbxTarget.fileSystemSynchronizedGroups ?? [],
            xcodeProj: xcodeProj
        )

        // Core Data models
        let resourceFiles = try pbxTarget.resourcesBuildPhase()?.files ?? []
        let coreDataModels = try coreDataModelsMapper.map(resourceFiles, xcodeProj: xcodeProj)

        // Frameworks & libraries
        let frameworksPhase = try pbxTarget.frameworksBuildPhase()
        var frameworks = try frameworksPhase.map {
            try frameworksMapper.map(
                $0,
                xcodeProj: xcodeProj,
                projectNativeTargets: projectNativeTargets
            )
        } ?? []

        frameworks = try await fileSystemSynchronizedGroupsFrameworks(
            from: pbxTarget,
            xcodeProj: xcodeProj
        ) + frameworks

        // Additional files (not in build phases)
        let additionalFiles = try mapAdditionalFiles(from: pbxTarget, xcodeProj: xcodeProj)

        // Resource elements
        let resourceFileElements = ResourceFileElements(resources)

        // Build Rules
        let buildRules = try pbxTarget.buildRules.compactMap { try buildRuleMapper.map($0) }

        // Files group
        let filesGroup = try extractFilesGroup(from: pbxTarget, xcodeProj: xcodeProj)

        // Swift Playgrounds
        let playgrounds = try extractPlaygrounds(from: pbxTarget, xcodeProj: xcodeProj)

        // Misc
        let mergedBinaryType = try pbxTarget.mergedBinaryType()
        let onDemandResourcesTags = try pbxTarget.onDemandResourcesTags()

        // Dependencies
        let projectNativeTargets = try pbxTarget.dependencies.compactMap {
            try dependencyMapper.map($0, xcodeProj: xcodeProj)
        }
        let allDependencies = (projectNativeTargets + frameworks + resourceDependencies).sorted { $0.name < $1.name }

        // Construct final Target
        return Target(
            name: pbxTarget.name,
            destinations: platform,
            product: product,
            productName: pbxTarget.productName ?? pbxTarget.name,
            bundleId: try pbxTarget.bundleIdentifier(),
            deploymentTargets: deploymentTargets,
            infoPlist: try await extractInfoPlist(from: pbxTarget, xcodeProj: xcodeProj),
            entitlements: try extractEntitlements(from: pbxTarget, xcodeProj: xcodeProj),
            settings: settings,
            sources: sources,
            resources: resourceFileElements,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            filesGroup: filesGroup,
            dependencies: allDependencies,
            rawScriptBuildPhases: rawScriptBuildPhases,
            playgrounds: playgrounds,
            additionalFiles: additionalFiles,
            buildRules: buildRules,
            mergedBinaryType: mergedBinaryType,
            onDemandResourcesTags: onDemandResourcesTags,
            packages: packages
        )
    }

    // MARK: - Private helpers

    /// Identifies files not included in any build phase, returning them as `FileElement` models.
    private func mapAdditionalFiles(from pbxTarget: PBXTarget, xcodeProj: XcodeProj) throws -> [FileElement] {
        guard let pbxProject = xcodeProj.pbxproj.projects.first,
              let mainGroup = pbxProject.mainGroup
        else {
            throw PBXTargetMappingError.noProjectsFound(path: xcodeProj.projectPath.pathString)
        }

        let allFiles = try collectAllFiles(from: mainGroup, xcodeProj: xcodeProj)
        let filesInBuildPhases = try filesReferencedByBuildPhases(pbxTarget: pbxTarget, xcodeProj: xcodeProj)
        let additionalFiles = allFiles.subtracting(filesInBuildPhases).sorted()
        return additionalFiles.map { FileElement.file(path: $0) }
    }

    /// Extracts the main files group for the target.
    private func extractFilesGroup(from target: PBXTarget, xcodeProj: XcodeProj) throws -> ProjectGroup {
        guard let pbxProject = xcodeProj.pbxproj.projects.first,
              let mainGroup = pbxProject.mainGroup
        else {
            throw PBXTargetMappingError.missingFilesGroup(targetName: target.name)
        }
        return ProjectGroup.group(name: mainGroup.name ?? "MainGroup")
    }

    /// Extracts and parses the project's Info.plist as a dictionary, or returns an empty dictionary if none is found.
    private func extractInfoPlist(from target: PBXTarget, xcodeProj: XcodeProj) async throws -> InfoPlist {
        if let (config, plistPath) = target.infoPlistPaths().sorted(by: { $0.key.name > $1.key.name }).first {
            let pathString = plistPath
                .replacingOccurrences(of: "$(SRCROOT)", with: xcodeProj.srcPathString)
                .replacingOccurrences(of: "$(PROJECT_DIR)", with: xcodeProj.projectPath.parentDirectory.pathString)
            let path = if pathString.starts(with: "/") {
                try AbsolutePath(validating: pathString)
            } else {
                xcodeProj.srcPath.appending(try RelativePath(validating: pathString))
            }
            return .file(path: path, configuration: config)
        }
        return .dictionary([:])
    }

    /// Extracts the target's entitlements file, if present.
    private func extractEntitlements(from target: PBXTarget, xcodeProj: XcodeProj) throws -> Entitlements? {
        let entitlementsMap = target.entitlementsPath()
        guard let configuration = target.defaultBuildConfiguration() ?? entitlementsMap.keys.first else { return nil }
        guard let entitlementsPath = entitlementsMap[configuration] else { return nil }

        let path = xcodeProj.srcPath.appending(try RelativePath(validating: entitlementsPath))
        return Entitlements.file(path: path, configuration: configuration)
    }

    /// Recursively collects all files from a given `PBXGroup`.
    private func collectAllFiles(from group: PBXGroup, xcodeProj: XcodeProj) throws -> Set<AbsolutePath> {
        var files = Set<AbsolutePath>()
        for child in group.children {
            if let file = child as? PBXFileReference,
               let pathString = try file.fullPath(sourceRoot: xcodeProj.srcPathString)
            {
                let path = try AbsolutePath(validating: pathString)
                files.insert(path)
            } else if let subgroup = child as? PBXGroup {
                files.formUnion(try collectAllFiles(from: subgroup, xcodeProj: xcodeProj))
            }
        }
        return files
    }

    /// Identifies all files referenced by any build phase in the target.
    private func filesReferencedByBuildPhases(
        pbxTarget: PBXTarget,
        xcodeProj: XcodeProj
    ) throws -> Set<AbsolutePath> {
        let filePaths = try pbxTarget.buildPhases
            .compactMap(\.files)
            .flatMap { $0 }
            .compactMap { buildFile -> AbsolutePath? in
                guard let fileRef = buildFile.file,
                      let filePath = try fileRef.fullPath(sourceRoot: xcodeProj.srcPathString)
                else {
                    return nil
                }
                return try AbsolutePath(validating: filePath)
            }
        return Set(filePaths)
    }

    /// Extracts playground files from the target's sources.
    private func extractPlaygrounds(from pbxTarget: PBXTarget, xcodeProj: XcodeProj) throws -> [AbsolutePath] {
        let sources = try pbxTarget.sourcesBuildPhase().map {
            try sourcesMapper.map($0, xcodeProj: xcodeProj)
        } ?? []
        return sources.filter { $0.path.fileExtension == .playground }.map(\.path)
    }

    /// Converts a raw plist value into a `Plist.Value`.
    private func convertToPlistValue(_ value: Any) throws -> Plist.Value {
        switch value {
        case let stringValue as String:
            return .string(stringValue)
        case let intValue as Int:
            return .integer(intValue)
        case let doubleValue as Double:
            return .real(doubleValue)
        case let boolValue as Bool:
            return .boolean(boolValue)
        case let arrayValue as [Any]:
            let converted = try arrayValue.map { try convertToPlistValue($0) }
            return .array(converted)
        case let dictValue as [String: Any]:
            let converted = try dictValue.reduce(into: [String: Plist.Value]()) { dictResult, entry in
                dictResult[entry.key] = try convertToPlistValue(entry.value)
            }
            return .dictionary(converted)
        default:
            // If unrecognized, store its string description
            return .string(String(describing: value))
        }
    }

    private func fileSystemSynchronizedGroupsSources(
        from pbxTarget: PBXTarget,
        xcodeProj: XcodeProj,
        packages: [AbsolutePath]
    ) async throws -> [SourceFile] {
        guard let fileSystemSynchronizedGroups = pbxTarget.fileSystemSynchronizedGroups else { return [] }
        var sources: [SourceFile] = []
        for fileSystemSynchronizedGroup in fileSystemSynchronizedGroups {
            if let path = fileSystemSynchronizedGroup.path {
                let membershipExceptions = membershipExceptions(for: fileSystemSynchronizedGroup)
                let additionalCompilerFlagsByRelativePath: [String: String]? = fileSystemSynchronizedGroup.exceptions?
                    .reduce(into: [:]) { acc, element in
                        guard let element = element as? PBXFileSystemSynchronizedBuildFileExceptionSet else { return }
                        acc.merge(element.additionalCompilerFlagsByRelativePath ?? [:], uniquingKeysWith: { $1 })
                    }
                let directory = xcodeProj.srcPath.appending(component: path)
                let groupSources = try await globFiles(
                    directory: directory,
                    include: [
                        // Build glob patterns for source files and source-compatible folders.
                        // This creates patterns like "**/*.{m,swift,mm,...}".
                        "**/*.{\(Target.validSourceExtensions.joined(separator: ","))}",
                        "**/*.{\(Target.validSourceCompatibleFolderExtensions.joined(separator: ","))}",
                    ],
                    membershipExceptions: membershipExceptions
                )
                .filter { path in
                    !packages.contains(where: { $0.isAncestor(of: path) })
                }
                .map {
                    SourceFile(
                        path: $0,
                        compilerFlags: additionalCompilerFlagsByRelativePath?[$0.relative(to: directory).pathString]
                    )
                }
                sources.append(contentsOf: groupSources)
            }
        }
        return sources
    }

    private func fileSystemSynchronizedGroupsResources(
        from pbxTarget: PBXTarget,
        xcodeProj: XcodeProj
    ) async throws -> [ResourceFileElement] {
        let fileSystemSynchronizedGroups = pbxTarget.fileSystemSynchronizedGroups ?? []
        var resources: [ResourceFileElement] = []
        for fileSystemSynchronizedGroup in fileSystemSynchronizedGroups {
            guard let path = fileSystemSynchronizedGroup.path else { continue }
            let directory = xcodeProj.srcPath.appending(component: path)
            let membershipExceptions = membershipExceptions(for: fileSystemSynchronizedGroup)

            let groupResources = try await globFiles(
                directory: directory,
                include: [
                    // Build glob patterns for resource files and resource-compatible folders.
                    // This creates patterns like "**/*.{xcassets,png,...}".
                    "**/*.{\(Target.validResourceExtensions.joined(separator: ","))}",
                    "**/*.{\(Target.validResourceCompatibleFolderExtensions.joined(separator: ","))}",
                ],
                membershipExceptions: membershipExceptions
            )
            .map {
                ResourceFileElement(path: $0)
            }
            resources.append(contentsOf: groupResources)
        }

        return resources
    }

    private func fileSystemSynchronizedGroupsFrameworks(
        from pbxTarget: PBXTarget,
        xcodeProj: XcodeProj
    ) async throws -> [TargetDependency] {
        let fileSystemSynchronizedGroups = pbxTarget.fileSystemSynchronizedGroups ?? []
        var frameworks: [TargetDependency] = []
        for fileSystemSynchronizedGroup in fileSystemSynchronizedGroups {
            guard let path = fileSystemSynchronizedGroup.path else { continue }
            let directory = xcodeProj.srcPath.appending(component: path)
            let membershipExceptions = membershipExceptions(for: fileSystemSynchronizedGroup)
            let attributesByRelativePath = fileSystemSynchronizedGroup.exceptions?
                .compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }.reduce([:]) { acc, element in
                    acc.merging(element.attributesByRelativePath ?? [:], uniquingKeysWith: { $1 })
                }

            let groupFrameworks: [TargetDependency] = try await globFiles(
                directory: directory,
                include: [
                    "**/*.framework",
                ],
                membershipExceptions: membershipExceptions
            )
            .map {
                return .framework(
                    path: $0,
                    status: attributesByRelativePath?[$0.relative(to: directory).pathString]?
                        .contains("Weak") == true ? .optional : .required,
                    condition: nil
                )
            }
            frameworks.append(contentsOf: groupFrameworks)
        }

        return frameworks
    }

    private func addHeadersFromFileSystemSynchronizedGroups(
        from pbxTarget: PBXTarget,
        xcodeProj: XcodeProj,
        headers: Headers?
    ) async throws -> Headers? {
        let fileSystemSynchronizedGroups = pbxTarget.fileSystemSynchronizedGroups ?? []
        var publicHeaders = headers?.public ?? []
        var privateHeaders = headers?.private ?? []
        var projectHeaders = headers?.project ?? []
        for fileSystemSynchronizedGroup in fileSystemSynchronizedGroups {
            guard let path = fileSystemSynchronizedGroup.path else { continue }
            let directory = xcodeProj.srcPath.appending(component: path)
            for synchronizedBuildFileSystemExceptionSet in fileSystemSynchronizedGroup.exceptions?
                .compactMap({ $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }) ?? []
            {
                for publicHeader in synchronizedBuildFileSystemExceptionSet.publicHeaders ?? [] {
                    publicHeaders.append(directory.appending(component: publicHeader))
                }
                for privateHeader in synchronizedBuildFileSystemExceptionSet.privateHeaders ?? [] {
                    privateHeaders.append(directory.appending(component: privateHeader))
                }
            }
            let membershipExceptions = membershipExceptions(for: fileSystemSynchronizedGroup)

            let publicHeadersSet = Set(publicHeaders)
            let privateHeadersSet = Set(privateHeaders)

            let groupHeaders = try await globFiles(
                directory: directory,
                include: [
                    "**/*.{h,hpp}",
                ],
                membershipExceptions: membershipExceptions
            )
            .filter {
                !privateHeadersSet.contains($0) && !publicHeadersSet.contains($0)
            }
            projectHeaders.append(contentsOf: groupHeaders)
        }
        if !publicHeaders.isEmpty || !privateHeaders.isEmpty || !projectHeaders.isEmpty || headers != nil {
            return Headers(
                public: publicHeaders,
                private: privateHeaders,
                project: projectHeaders
            )
        } else {
            return headers
        }
    }

    private func membershipExceptions(for fileSystemSynchronizedGroup: PBXFileSystemSynchronizedRootGroup) -> Set<String> {
        Set(
            fileSystemSynchronizedGroup.exceptions
                .map { $0.compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet } }
                .map { $0.compactMap(\.membershipExceptions).flatMap { $0 } } ?? []
        )
    }

    /// Performs a glob search in the given directory using specified patterns, filtering out paths
    /// that appear in the membershipExceptions set.
    private func globFiles(
        directory: AbsolutePath,
        include: [String],
        membershipExceptions: Set<String>
    ) async throws -> [AbsolutePath] {
        return try await fileSystem.glob(
            directory: directory,
            include: include
        )
        .collect()
        .filter { !membershipExceptions.contains($0.relative(to: directory).pathString) }
    }
}

// swiftlint:enable function_body_length
// swiftlint:enable type_body_length
