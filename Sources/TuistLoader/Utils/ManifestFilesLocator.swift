import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

@Mockable
public protocol ManifestFilesLocating: AnyObject {
    /// It locates the manifest files in the locating directory.
    /// - Parameter locatingPath: Directory for which the manifest files will be obtained.
    func locateManifests(at locatingPath: AbsolutePath) async throws -> [(Manifest, AbsolutePath)]

    /// It locates all plugin manifest files under the the root directory (as defined in `RootDirectoryLocator`).
    /// - Parameters:
    ///     - locatingPath: Directory for which the **plugin** manifest files will be obtained.
    ///     - excluding: Relative glob patterns for excluded files.
    ///     - onlyCurrentDirectory: If true, search for plugin manifests only in the directory of `locatingPath`
    func locatePluginManifests(
        at locatingPath: AbsolutePath,
        excluding: [String],
        onlyCurrentDirectory: Bool
    ) async throws -> [AbsolutePath]

    /// It locates all project and workspace manifest files under the root directory (as defined in `RootDirectoryLocator`).
    /// - Parameters:
    ///     - locatingPath: Directory for which the **project** and **workspace** manifest files will be obtained.
    ///     - excluding: Relative glob patterns for excluded files.
    ///     - onlyCurrentDirectory: If true, search for manifests only in the directory of `locatingPath`
    func locateProjectManifests(
        at locatingPath: AbsolutePath,
        excluding: [String],
        onlyCurrentDirectory: Bool
    ) async throws -> [ManifestFilesLocator.ProjectManifest]

    /// It traverses up the directory hierarchy until it finds a `Tuist.swift` file.
    /// - Parameter locatingPath: Path from where to do the lookup.
    func locateConfig(at locatingPath: AbsolutePath) async throws -> AbsolutePath?

    /// It traverses up the directory hierarchy until it finds a `Package.swift` file
    /// - Parameter locatingPath: Path from where to do the lookup
    func locatePackageManifest(
        at locatingPath: AbsolutePath
    ) async throws -> AbsolutePath?
}

public final class ManifestFilesLocator: ManifestFilesLocating {
    /// Utility to locate the root directory of the project
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming

    public init(
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileSystem = fileSystem
    }

    public func locateManifests(at locatingPath: AbsolutePath) async throws -> [(Manifest, AbsolutePath)] {
        let fileSystem = fileSystem
        return try await Manifest.allCases.concurrentCompactMap { manifest in
            let path = locatingPath.appending(component: manifest.fileName(locatingPath))
            if try await fileSystem.exists(path) { return (manifest, path) }
            return nil
        }
    }

    public func locatePluginManifests(
        at locatingPath: AbsolutePath,
        excluding: [String],
        onlyCurrentDirectory: Bool
    ) async throws -> [AbsolutePath] {
        if onlyCurrentDirectory {
            let pluginPath = locatingPath.appending(
                component: Manifest.plugin.fileName(locatingPath)
            )
            guard try await fileSystem.exists(pluginPath) else { return [] }
            return [pluginPath]
        } else {
            let path = try await rootDirectoryLocator.locate(from: locatingPath) ?? locatingPath

            let pluginsPaths = await fetchTuistManifestsFilePaths(at: path)
                .filter { $0.basename == Manifest.plugin.fileName(path) }
                .filter { path in
                    !excluding.contains { pattern in match(path, pattern: pattern) }
                }

            return Array(pluginsPaths)
        }
    }

    private func match(_ path: AbsolutePath, pattern: String) -> Bool {
        fnmatch(pattern, path.pathString, 0) != FNM_NOMATCH
    }

    var cacheTuistManifestsFilePaths = [AbsolutePath: Set<AbsolutePath>]()

    private func fetchTuistManifestsFilePaths(at path: AbsolutePath) async -> Set<AbsolutePath> {
        if let cachedTuistManifestsFilePaths = cacheTuistManifestsFilePaths[path] {
            return cachedTuistManifestsFilePaths
        }
        let fileNamesCandidates: Set<String> = [
            Manifest.project.fileName(path),
            Manifest.workspace.fileName(path),
            Manifest.plugin.fileName(path),
        ]

        let tuistManifestsFilePaths = await FileHandler.shared.files(
            in: path,
            nameFilter: fileNamesCandidates,
            extensionFilter: ["swift"]
        ).concurrentFilter { [weak self] in
            await self?.hasValidManifestContent($0) ?? false
        }

        cacheTuistManifestsFilePaths[path] = tuistManifestsFilePaths

        return tuistManifestsFilePaths
    }

    private func hasValidManifestContent(_ path: AbsolutePath) async -> Bool {
        guard let content = try? await fileSystem.readTextFile(at: path) else { return false }

        let tuistManifestSignature = "import ProjectDescription"
        return content.contains(tuistManifestSignature) || content.isEmpty
    }

    /// Project manifest returned by `locateProjectManifests`
    public struct ProjectManifest: Equatable {
        public let manifest: Manifest
        public let path: AbsolutePath

        public init(
            manifest: Manifest,
            path: AbsolutePath
        ) {
            self.manifest = manifest
            self.path = path
        }
    }

    public func locateProjectManifests(
        at locatingPath: AbsolutePath,
        excluding: [String],
        onlyCurrentDirectory: Bool
    ) async throws -> [ProjectManifest] {
        let fileSystem = fileSystem

        if onlyCurrentDirectory {
            return try await [
                ProjectManifest(
                    manifest: Manifest.project,
                    path: locatingPath.appending(
                        component: Manifest.project.fileName(locatingPath)
                    )
                ),
                ProjectManifest(
                    manifest: Manifest.workspace,
                    path: locatingPath.appending(
                        component: Manifest.workspace.fileName(locatingPath)
                    )
                ),
            ]
            .concurrentFilter { try await fileSystem.exists($0.path) }
        } else {
            let path = try await rootDirectoryLocator.locate(from: locatingPath) ?? locatingPath

            let manifestsFilePaths = await fetchTuistManifestsFilePaths(at: path)
                .filter { path in
                    !excluding.contains { pattern in match(path, pattern: pattern) }
                }
            let projectsPaths = manifestsFilePaths
                .filter { $0.basename == Manifest.project.fileName(path) }
                .map {
                    ProjectManifest(
                        manifest: Manifest.project,
                        path: $0
                    )
                }
            let workspacesPaths = manifestsFilePaths
                .filter { $0.basename == Manifest.workspace.fileName(path) }
                .map {
                    ProjectManifest(
                        manifest: Manifest.workspace,
                        path: $0
                    )
                }

            return projectsPaths + workspacesPaths
        }
    }

    public func locateConfig(at locatingPath: AbsolutePath) async throws -> AbsolutePath? {
        if let path = try await traverseUpAndLocate(
            at: locatingPath,
            appending: [
                (component: "Tuist.swift", isDirectory: false),
                (component: Constants.tuistDirectoryName, isDirectory: true),
            ]
        ) {
            if path.basename == "Tuist.swift" {
                return path
            } else {
                // Tuist directory
                let configSwiftPath = path.appending(component: Manifest.config.fileName(locatingPath))
                if try await fileSystem.exists(configSwiftPath) { return configSwiftPath }
                return nil
            }
        } else {
            return nil
        }
    }

    public func locatePackageManifest(at locatingPath: AbsolutePath) async throws -> AbsolutePath? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: locatingPath) else { return nil }
        let defaultPackageSwiftPath = rootDirectory.appending(
            components: [
                Constants.tuistDirectoryName,
                Constants.SwiftPackageManager.packageSwiftName,
            ]
        )
        let rootPackageSwiftPath = rootDirectory
            .appending(component: Constants.SwiftPackageManager.packageSwiftName)
        if try await fileSystem.exists(defaultPackageSwiftPath) {
            return defaultPackageSwiftPath
        } else if try await fileSystem.exists(rootPackageSwiftPath) {
            return rootPackageSwiftPath
        } else {
            return nil
        }
    }

    // MARK: - Helpers

    private func traverseUpAndLocate(
        at locatingPath: AbsolutePath,
        appending subpaths: [(component: String, isDirectory: Bool)]
    ) async throws -> AbsolutePath? {
        for subpath in subpaths {
            let checkedPath = locatingPath.appending(try RelativePath(validating: subpath.component))
            if try await fileSystem.exists(checkedPath, isDirectory: subpath.isDirectory) {
                return checkedPath
            }
        }
        if locatingPath != .root {
            return try await traverseUpAndLocate(at: locatingPath.parentDirectory, appending: subpaths)
        } else {
            return nil
        }
    }
}
