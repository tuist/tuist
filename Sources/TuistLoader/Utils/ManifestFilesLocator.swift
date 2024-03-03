import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol ManifestFilesLocating: AnyObject {
    /// It locates the manifest files in the locating directory.
    /// - Parameter locatingPath: Directory for which the manifest files will be obtained.
    func locateManifests(at locatingPath: AbsolutePath) -> [(Manifest, AbsolutePath)]

    /// It locates all plugin manifest files under the the root directory (as defined in `RootDirectoryLocator`).
    /// - Parameters:
    ///     - locatingPath: Directory for which the **plugin** manifest files will be obtained.
    ///     - excluding: Relative glob patterns for excluded files.
    ///     - onlyCurrentDirectory: If true, search for plugin manifests only in the directory of `locatingPath`
    func locatePluginManifests(
        at locatingPath: AbsolutePath,
        excluding: [String],
        onlyCurrentDirectory: Bool
    ) -> [AbsolutePath]

    /// It locates all project and workspace manifest files under the root directory (as defined in `RootDirectoryLocator`).
    /// - Parameters:
    ///     - locatingPath: Directory for which the **project** and **workspace** manifest files will be obtained.
    ///     - excluding: Relative glob patterns for excluded files.
    ///     - onlyCurrentDirectory: If true, search for manifests only in the directory of `locatingPath`
    func locateProjectManifests(
        at locatingPath: AbsolutePath,
        excluding: [String],
        onlyCurrentDirectory: Bool
    ) -> [ManifestFilesLocator.ProjectManifest]

    /// It traverses up the directory hierarchy until it finds a `Config.swift` file.
    /// - Parameter locatingPath: Path from where to do the lookup.
    func locateConfig(at locatingPath: AbsolutePath) -> AbsolutePath?

    /// It traverses up the directory hierarchy until it finds a `Package.swift` file
    /// - Parameter locatingPath: Path from where to do the lookup
    func locatePackageManifest(
        at locatingPath: AbsolutePath
    ) -> AbsolutePath?
}

public final class ManifestFilesLocator: ManifestFilesLocating {
    /// Utility to locate the root directory of the project
    let rootDirectoryLocator: RootDirectoryLocating
    let fileHandler: FileHandling

    public init(
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileHandler = fileHandler
    }

    public func locateManifests(at locatingPath: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        Manifest.allCases.compactMap { manifest in
            let path = locatingPath.appending(component: manifest.fileName(locatingPath))
            if fileHandler.exists(path) { return (manifest, path) }
            return nil
        }
    }

    public func locatePluginManifests(
        at locatingPath: AbsolutePath,
        excluding: [String],
        onlyCurrentDirectory: Bool
    ) -> [AbsolutePath] {
        if onlyCurrentDirectory {
            let pluginPath = locatingPath.appending(
                component: Manifest.plugin.fileName(locatingPath)
            )
            guard fileHandler.exists(pluginPath) else { return [] }
            return [pluginPath]
        } else {
            let path = rootDirectoryLocator.locate(from: locatingPath) ?? locatingPath

            let pluginsPaths = fetchTuistManifestsFilePaths(at: path)
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

    private func fetchTuistManifestsFilePaths(at path: AbsolutePath) -> Set<AbsolutePath> {
        if let cachedTuistManifestsFilePaths = cacheTuistManifestsFilePaths[path] {
            return cachedTuistManifestsFilePaths
        }
        let fileNamesCandidates: Set<String> = [
            Manifest.project.fileName(path),
            Manifest.workspace.fileName(path),
            Manifest.plugin.fileName(path),
        ]

        let tuistManifestsFilePaths = FileHandler.shared.files(
            in: path,
            nameFilter: fileNamesCandidates,
            extensionFilter: ["swift"]
        ).filter {
            hasValidManifestContent($0)
        }

        cacheTuistManifestsFilePaths[path] = tuistManifestsFilePaths

        return tuistManifestsFilePaths
    }

    private func hasValidManifestContent(_ path: AbsolutePath) -> Bool {
        guard let content = try? fileHandler.readTextFile(path) else { return false }

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
    ) -> [ProjectManifest] {
        if onlyCurrentDirectory {
            return [
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
            .filter { fileHandler.exists($0.path) }
        } else {
            let path = rootDirectoryLocator.locate(from: locatingPath) ?? locatingPath

            let manifestsFilePaths = fetchTuistManifestsFilePaths(at: path)
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

    public func locateConfig(at locatingPath: AbsolutePath) -> AbsolutePath? {
        guard let tuistDirectory = traverseAndLocateTuistDirectory(at: locatingPath) else { return nil }
        let configSwiftPath = tuistDirectory.appending(component: Manifest.config.fileName(locatingPath))
        if fileHandler.exists(configSwiftPath) { return configSwiftPath }
        return nil
    }

    public func locatePackageManifest(at locatingPath: AbsolutePath) -> AbsolutePath? {
        guard let rootDirectory = rootDirectoryLocator.locate(from: locatingPath) else { return nil }
        let defaultPackageSwiftPath = rootDirectory.appending(
            components: [
                Constants.tuistDirectoryName,
                Constants.SwiftPackageManager.packageSwiftName,
            ]
        )
        let rootPackageSwiftPath = rootDirectory
            .appending(component: Constants.SwiftPackageManager.packageSwiftName)
        if fileHandler.exists(defaultPackageSwiftPath) {
            return defaultPackageSwiftPath
        } else if fileHandler.exists(rootPackageSwiftPath) {
            return rootPackageSwiftPath
        } else {
            return nil
        }
    }

    // MARK: - Helpers

    private func traverseAndLocateTuistDirectory(at locatingPath: AbsolutePath) -> AbsolutePath? {
        // swiftlint:disable:next force_try
        return traverseAndLocate(at: locatingPath, appending: try! RelativePath(validating: Constants.tuistDirectoryName))
    }

    private func traverseAndLocate(at locatingPath: AbsolutePath, appending subpath: RelativePath) -> AbsolutePath? {
        let manifestPath = locatingPath.appending(subpath)

        if fileHandler.exists(manifestPath) {
            return manifestPath
        } else if locatingPath != .root {
            return traverseAndLocate(at: locatingPath.parentDirectory, appending: subpath)
        } else {
            return nil
        }
    }
}
