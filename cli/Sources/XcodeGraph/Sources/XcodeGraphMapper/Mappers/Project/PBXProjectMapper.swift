import FileSystem
import Foundation
import Mockable
import Path
import PathKit
import XcodeGraph
import XcodeMetadata
@preconcurrency import XcodeProj

// swiftlint:disable function_body_length

/// A protocol for mapping an Xcode project (`.xcodeproj`) into a `Project` domain model.
@Mockable
protocol PBXProjectMapping {
    /// Maps the given `XcodeProj` into a `Project` model.
    ///
    /// - Parameter xcodeProj: The Xcode project to be transformed.
    /// - Returns: A fully constructed `Project` model.
    /// - Throws: If reading or transforming project data fails.
    func map(
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) async throws -> Project
}

/// A mapper that transforms a `.xcodeproj` into a `Project` domain model.
///
/// This process involves:
/// - Mapping project-level settings.
/// - Converting `PBXTarget`s into `Target` models.
/// - Resolving both remote and local Swift packages.
/// - Identifying and integrating user and shared schemes.
/// - Providing resource synthesizers for code generation.
struct PBXProjectMapper: PBXProjectMapping {
    private let fileSystem: FileSysteming
    private let targetMapper: PBXTargetMapping

    init(
        fileSystem: FileSysteming = FileSystem(),
        targetMapper: PBXTargetMapping = PBXTargetMapper()
    ) {
        self.fileSystem = fileSystem
        self.targetMapper = targetMapper
    }

    /// Maps the given Xcode project into a `Project` model.
    ///
    /// - Parameter xcodeProj: The Xcode project reference containing `.pbxproj` data.
    /// - Returns: A fully constructed `Project` model.
    /// - Throws: If reading or transforming project data fails.
    func map(
        xcodeProj: XcodeProj,
        projectNativeTargets: [String: ProjectNativeTarget]
    ) async throws -> Project {
        let settingsMapper = XCConfigurationMapper()
        let pbxProject = try xcodeProj.mainPBXProject()
        let xcodeProjPath = xcodeProj.projectPath
        let sourceDirectory = xcodeProjPath.parentDirectory

        // Map the project-wide build settings
        let settings = try settingsMapper.map(
            xcodeProj: xcodeProj,
            configurationList: pbxProject.buildConfigurationList
        )

        let localPackagePaths = try await collectAllPackages(from: pbxProject.mainGroup, xcodeProj: xcodeProj)

        // Map PBXTargets to domain Targets
        let targets = try await withThrowingTaskGroup(of: Target?.self, returning: [Target].self) { taskGroup in
            let projectNativeTargets = projectNativeTargets
            for pbxTarget in pbxProject.targets {
                taskGroup.addTask {
                    try await targetMapper.map(
                        pbxTarget: pbxTarget,
                        xcodeProj: xcodeProj,
                        projectNativeTargets: projectNativeTargets,
                        packages: localPackagePaths
                    )
                }
            }

            var targets: [Target] = []
            for try await target in taskGroup {
                if let target {
                    targets.append(target)
                }
            }

            return targets
        }
        .sorted()

        // Map remote and local packages
        let packageMapper = XCPackageMapper()
        let remotePackages = try pbxProject.remotePackages.compactMap {
            try packageMapper.map(package: $0)
        }
        let localPackages = try pbxProject.localPackages.compactMap {
            try packageMapper.map(package: $0, sourceDirectory: sourceDirectory)
        } + localPackagePaths.map { .local(path: $0) }

        // Create a files group for the main group
        let filesGroup = ProjectGroup.group(name: pbxProject.mainGroup?.name ?? "Project")

        // Map user and shared schemes
        let schemeMapper = XCSchemeMapper()
        let graphType: XcodeMapperGraphType = .project(xcodeProj)
        var userSchemes: [Scheme] = []
        for scheme in xcodeProj.userData.flatMap(\.schemes) {
            userSchemes.append(
                try await schemeMapper.map(scheme, shared: false, graphType: graphType)
            )
        }
        var sharedSchemes: [Scheme] = []
        for scheme in xcodeProj.sharedData?.schemes ?? [] {
            sharedSchemes.append(
                try await schemeMapper.map(scheme, shared: true, graphType: graphType)
            )
        }
        let schemes = userSchemes + sharedSchemes

        // Other project-level metadata
        let lastUpgradeCheck = pbxProject.attribute(for: .lastUpgradeCheck).flatMap { Version(string: $0) }
        let defaultKnownRegions = pbxProject.knownRegions.isEmpty ? nil : pbxProject.knownRegions

        // Construct the final `Project`
        return Project(
            path: sourceDirectory,
            sourceRootPath: sourceDirectory,
            xcodeProjPath: xcodeProjPath,
            name: pbxProject.name,
            organizationName: pbxProject.attribute(for: .organization),
            classPrefix: pbxProject.attribute(for: .classPrefix),
            defaultKnownRegions: defaultKnownRegions,
            developmentRegion: pbxProject.developmentRegion,
            options: .init(
                automaticSchemesOptions: .disabled,
                disableBundleAccessors: false,
                disableShowEnvironmentVarsInScriptPhases: false,
                disableSynthesizedResourceAccessors: false,
                textSettings: .init(
                    usesTabs: nil,
                    indentWidth: nil,
                    tabWidth: nil,
                    wrapsLines: nil
                )
            ),
            settings: settings,
            filesGroup: filesGroup,
            targets: targets,
            packages: remotePackages + localPackages,
            schemes: schemes,
            ideTemplateMacros: nil,
            additionalFiles: [],
            resourceSynthesizers: mapResourceSynthesizers(),
            lastUpgradeCheck: lastUpgradeCheck,
            type: .local
        )
    }

    /// Returns a set of default resource synthesizers for common resource types.
    private func mapResourceSynthesizers() -> [ResourceSynthesizer] {
        ResourceSynthesizer.Parser.allCases.map { parser in
            let (exts, template) = parser.resourceTypes()
            return ResourceSynthesizer(
                parser: parser,
                parserOptions: [:],
                extensions: Set(exts),
                template: .defaultTemplate(template)
            )
        }
    }

    private func collectAllPackages(from group: PBXGroup, xcodeProj: XcodeProj) async throws -> [AbsolutePath] {
        var packages = Set<AbsolutePath>()
        for child in group.children {
            if let file = child as? PBXFileReference,
               let pathString = try file.fullPath(sourceRoot: xcodeProj.srcPathString)
            {
                let path = try AbsolutePath(validating: pathString)
                if (try? await fileSystem.exists(path, isDirectory: true)) ?? false,
                   try await fileSystem.exists(path.appending(component: "Package.swift"))
                {
                    packages.insert(path)
                }
            } else if let subgroup = child as? PBXGroup {
                packages.formUnion(try await collectAllPackages(from: subgroup, xcodeProj: xcodeProj))
            } else if let subgroup = child as? PBXFileSystemSynchronizedRootGroup, let synchronizedGroupPath = subgroup.path {
                let directory = xcodeProj.srcPath.appending(component: synchronizedGroupPath)
                let groupPackages = try await fileSystem.glob(
                    directory: directory,
                    include: [
                        "**/Package.swift",
                    ]
                )
                .collect()
                .map(\.parentDirectory)
                packages.formUnion(groupPackages)
            }
        }
        return Array(packages)
    }
}

// MARK: - ResourceSynthesizer.Parser Helpers

extension ResourceSynthesizer.Parser {
    /// Defines resource extensions and default templates for each parser type.
    fileprivate func resourceTypes() -> (exts: [String], template: String) {
        switch self {
        case .strings, .stringsCatalog:
            return (["strings", "stringsdict"], "Strings")
        case .assets:
            return (["xcassets"], "Assets")
        case .plists:
            return (["plist"], "Plists")
        case .fonts:
            return (["ttf", "otf", "ttc"], "Fonts")
        case .coreData:
            return (["xcdatamodeld"], "CoreData")
        case .interfaceBuilder:
            return (["xib", "storyboard"], "InterfaceBuilder")
        case .json:
            return (["json"], "JSON")
        case .yaml:
            return (["yaml", "yml"], "YAML")
        case .files:
            return (["txt", "md"], "Files")
        }
    }
}

// swiftlint:enable function_body_length
