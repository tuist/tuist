import Foundation
import Logging
import Path
import TuistConfig
import TuistCore
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
/// Every project gets the SwiftPM scratch directory mapped to `/^spm` and the
/// workspace directory mapped to `/^workspace`, through `SWIFT_OTHER_PREFIX_MAPPINGS`
/// and `CLANG_OTHER_PREFIX_MAPPINGS`. Xcode emits these after the project mappings, and
/// the scratch directory before the workspace directory that usually contains it, so a
/// path always resolves to its most specific placeholder.
///
/// The workspace directory is written once, to `TUIST_PREFIX_MAPPING_WORKSPACE_DIR`,
/// and the mappings reference it, so they read the same in every checkout and the
/// module cache hash can leave out just that one setting. Each mapping is quoted
/// because Xcode splits a list element at spaces.
public struct XcodeCachePrefixMappingWorkspaceMapper: WorkspaceMapping {
    static let prefixMappingSettings = ["SWIFT_OTHER_PREFIX_MAPPINGS", "CLANG_OTHER_PREFIX_MAPPINGS"]
    static let workspaceDirectorySetting = "TUIST_PREFIX_MAPPING_WORKSPACE_DIR"

    private let tuist: Tuist

    public init(tuist: Tuist) {
        self.tuist = tuist
    }

    public func map(workspace: WorkspaceWithProjects) async throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        guard tuist.project.generatedProject?.generationOptions.enableCaching ?? false,
              await XcodeCacheSettingsProjectMapper.isPrefixMappingSupported()
        else { return (workspace, []) }

        Logger.current.debug(
            "Transforming workspace \(workspace.workspace.name): Adding Xcode cache prefix mappings"
        )

        let workspaceDirectory = workspace.workspace.xcWorkspacePath.parentDirectory
        let mappings = Self.prefixMappings(
            scratchDirectories: Set(workspace.projects.compactMap(\.swiftPackageManagerScratchDirectory)),
            workspaceDirectory: workspaceDirectory
        )

        var workspace = workspace
        workspace.projects = workspace.projects.map { project in
            var project = project
            var base = project.settings.base
            base[Self.workspaceDirectorySetting] = .string(workspaceDirectory.pathString)
            for setting in Self.prefixMappingSettings {
                base[setting] = Self.appending(mappings, to: base[setting])
            }
            project.settings = project.settings.with(base: base)
            return project
        }
        return (workspace, [])
    }

    private static func prefixMappings(
        scratchDirectories: Set<AbsolutePath>,
        workspaceDirectory: AbsolutePath
    ) -> [String] {
        let root = "$(\(workspaceDirectorySetting))"
        let scratchMappings = scratchDirectories.sorted().enumerated().map { index, directory in
            let prefix = directory.isDescendant(of: workspaceDirectory)
                ? "\(root)/\(directory.relative(to: workspaceDirectory).pathString)"
                : directory.pathString
            return quoted("\(prefix)=/^spm\(index == 0 ? "" : "\(index + 1)")")
        }
        return scratchMappings + [quoted("\(root)=/^workspace")]
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
