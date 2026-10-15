import Foundation
import Logging
import Path
import TuistConfig
import TuistCore
import TuistRootDirectoryLocator
import XcodeGraph

/// Maps the directories that `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` and
/// `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` leave out of Xcode's compilation-cache keys.
///
/// Project prefix mapping covers only `PROJECT_DIR`, `PROJECT_TEMP_DIR` and
/// `BUILT_PRODUCTS_DIR`. An external package's `PROJECT_DIR` is its generated project
/// under `tuist-derived/Projects/`, while its sources, headers and module maps live in
/// the SwiftPM checkout next to it, so their absolute paths stay in the key and the
/// package misses the cache from any other checkout of the repository. The same holds
/// for first-party sources outside their own project directory, and for the package
/// headers and module maps a first-party target reads when it imports a package.
///
/// Every project gets the SwiftPM scratch directory mapped to `/^spm` and the Tuist
/// root directory mapped to `/^root`, through `SWIFT_OTHER_PREFIX_MAPPINGS` and
/// `CLANG_OTHER_PREFIX_MAPPINGS`. The compilation-cache scanners sort mappings so
/// nested prefixes take precedence, independent of the flag order. Keep the scratch
/// directory before the root for deterministic output, not to select the winning map.
/// Shared intermediate and product mappings keep build paths stable when a project
/// explicitly disables per-project mapping to avoid ambiguous `/^src` source paths.
///
/// The root is the directory the scratch directory is resolved from, not the generated
/// workspace's, which can sit below it (`tuist generate --path App`). That keeps the
/// default scratch directory, `Tuist/.build`, inside the root for every workspace.
///
/// The root directory is written once, to `TUIST_PREFIX_MAPPING_ROOT_DIR`, and the
/// mappings reference it, so they read the same in every checkout and the module cache
/// hash can leave out just that one setting. Each mapping is quoted because Xcode
/// splits a list element at spaces.
///
/// Packages added through `Project.packages` are checked out by Xcode into the
/// `SourcePackages` directory next to the build directory, mapped to `/^packages`. Xcode
/// builds them from their manifests, so their targets don't read the projects' settings:
/// Xcode 27 only passes `SWIFT_ENABLE_COMPILE_CACHE` down to them. The mapper writes the
/// same mappings into `XcodeCachePackagesXCConfig`, whose settings reach every target of
/// a build that passes it to `xcodebuild`. There they extend the projects' mappings with
/// `$(inherited)`, and they enable prefix mapping only where nothing else set it, with
/// the coverage gating of `XcodeCacheSettingsProjectMapper`.
public struct XcodeCachePrefixMappingWorkspaceMapper: WorkspaceMapping {
    static let prefixMappingSettings = ["SWIFT_OTHER_PREFIX_MAPPINGS", "CLANG_OTHER_PREFIX_MAPPINGS"]
    static let enablePrefixMappingSettings = ["SWIFT_ENABLE_PREFIX_MAPPING", "CLANG_ENABLE_PREFIX_MAPPING"]
    static let rootDirectorySetting = "TUIST_PREFIX_MAPPING_ROOT_DIR"
    static let sourcePackagesDirectorySetting = "TUIST_SOURCE_PACKAGES_DIR"
    /// Xcode checks packages out into `<DerivedData>/SourcePackages`, next to `Build`,
    /// and `OBJROOT` is `<DerivedData>/Build/Intermediates.noindex`.
    static let sourcePackagesDirectory = "$(OBJROOT)/../../SourcePackages"

    private let tuist: Tuist
    private let rootDirectoryLocator: RootDirectoryLocating

    public init(tuist: Tuist, rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.tuist = tuist
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func map(workspace: WorkspaceWithProjects) async throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        let xcconfigPath = XcodeCachePackagesXCConfig.path(xcWorkspacePath: workspace.workspace.xcWorkspacePath)
        let removeXCConfig = SideEffectDescriptor.file(FileDescriptor(path: xcconfigPath, state: .absent))

        guard tuist.project.generatedProject?.generationOptions.enableCaching ?? false,
              await XcodeCacheSettingsProjectMapper.isPrefixMappingSupported()
        else { return (workspace, [removeXCConfig]) }

        Logger.current.debug(
            "Transforming workspace \(workspace.workspace.name): Adding Xcode cache prefix mappings"
        )

        let rootDirectory = try await rootDirectoryLocator.locate(from: workspace.workspace.path)
            ?? workspace.workspace.xcWorkspacePath.parentDirectory
        let hasXcodePackages = workspace.projects.contains { !$0.packages.isEmpty }
        let mappings = Self.prefixMappings(
            scratchDirectories: Set(workspace.projects.compactMap(\.swiftPackageManagerScratchDirectory)),
            rootDirectory: rootDirectory,
            hasXcodePackages: hasXcodePackages
        )

        var workspace = workspace
        workspace.projects = workspace.projects.map { project in
            var project = project
            var base = project.settings.base
            base[Self.rootDirectorySetting] = .string(rootDirectory.pathString)
            if hasXcodePackages {
                base[Self.sourcePackagesDirectorySetting] = .string(Self.sourcePackagesDirectory)
            }
            for setting in Self.prefixMappingSettings {
                base[setting] = Self.appending(mappings, to: base[setting])
            }
            project.settings = project.settings.with(base: base)
            return project
        }

        guard hasXcodePackages else { return (workspace, [removeXCConfig]) }
        let xcconfig = Self.packagesXCConfig(mappings: mappings, rootDirectory: rootDirectory, tuist: tuist)
        return (workspace, [.file(FileDescriptor(path: xcconfigPath, contents: Data(xcconfig.utf8)))])
    }

    private static func prefixMappings(
        scratchDirectories: Set<AbsolutePath>,
        rootDirectory: AbsolutePath,
        hasXcodePackages: Bool
    ) -> [String] {
        let root = "$(\(rootDirectorySetting))"
        let scratchMappings = scratchDirectories.sorted().enumerated().map { index, directory in
            let prefix = directory.isDescendant(of: rootDirectory)
                ? "\(root)/\(directory.relative(to: rootDirectory).pathString)"
                : directory.pathString
            return quoted("\(prefix)=/^spm\(index == 0 ? "" : "\(index + 1)")")
        }
        let sourcePackagesMappings = hasXcodePackages
            ? [quoted("$(\(sourcePackagesDirectorySetting):standardizepath)=/^packages")]
            : []
        return scratchMappings + sourcePackagesMappings + [
            quoted("$(OBJROOT)=/^intermediates"),
            quoted("$(SYMROOT)=/^products"),
            quoted("\(root)=/^root"),
        ]
    }

    private static func packagesXCConfig(mappings: [String], rootDirectory: AbsolutePath, tuist: Tuist) -> String {
        var lines = [
            "// Generated by Tuist. Do not edit.",
            "//",
            "// Applies the Xcode cache prefix mappings to the targets of the packages in `Project.packages`,",
            "// which don't read the generated projects' build settings. `tuist xcodebuild`, `tuist build`",
            "// and `tuist test` pass it to xcodebuild through `XCODE_XCCONFIG_FILE`. Pass it to other",
            "// xcodebuild invocations with `-xcconfig`.",
            "",
            "\(rootDirectorySetting) = \(rootDirectory.pathString)",
            "\(sourcePackagesDirectorySetting) = \(sourcePackagesDirectory)",
        ]
        for (key, value) in XcodeCacheSettingsProjectMapper.prefixMappingForCoverageSettings(tuist: tuist) {
            lines.append("\(key) = \(value)")
        }
        let enabledUnlessCoverage = XcodeCacheSettingsProjectMapper.prefixMappingUnlessCoverageExpression
        for setting in enablePrefixMappingSettings {
            lines.append("\(setting) = $(inherited:default=\(enabledUnlessCoverage))")
        }
        for setting in prefixMappingSettings {
            lines.append("\(setting) = \((["$(inherited)"] + mappings).joined(separator: " "))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quotes `value` as a single element of a build setting list.
    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func appending(_ mappings: [String], to existing: SettingValue?) -> SettingValue {
        switch existing {
        case let .array(values):
            return .array(values + mappings)
        case let .string(value):
            return .array([value] + mappings)
        case nil:
            return .array(["$(inherited)"] + mappings)
        }
    }
}
