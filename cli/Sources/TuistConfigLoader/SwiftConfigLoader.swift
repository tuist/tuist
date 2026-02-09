#if os(macOS)
    import FileSystem
    import Foundation
    import Mockable
    import Path
    import struct ProjectDescription.Config
    import TuistAlert
    import TuistConfig
    import TuistConstants
    import TuistLoader
    import TuistRootDirectoryLocator
    import TuistSupport

    @Mockable
    protocol SwiftConfigLoading: Sendable {
        func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist
        func locateConfig(at: AbsolutePath) async throws -> AbsolutePath?
    }

    final class SwiftConfigLoader: SwiftConfigLoading {
        private let manifestLoader: ManifestLoading
        private let rootDirectoryLocator: RootDirectoryLocating
        private let fileSystem: FileSysteming
        private var cachedConfigs: [AbsolutePath: TuistConfig.Tuist] = [:]

        init(
            manifestLoader: ManifestLoading = ManifestLoader.current,
            rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.manifestLoader = manifestLoader
            self.rootDirectoryLocator = rootDirectoryLocator
            self.fileSystem = fileSystem
        }

        func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist {
            if let cached = cachedConfigs[path] {
                return cached
            }

            guard let configPath = try await locateConfig(at: path) else {
                let config = try await defaultConfig(at: path)
                cachedConfigs[path] = config
                return config
            }

            if configPath.pathString.contains("Config.swift") {
                AlertController.current
                    .warning(
                        .alert("Tuist/Config.swift is deprecated. Rename Tuist/Config.swift to Tuist.swift at the root.")
                    )
            }

            let manifest = try await manifestLoader.loadConfig(at: configPath.parentDirectory)
            let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: configPath)
            let config = try await TuistConfig.Tuist.from(
                manifest: manifest,
                rootDirectory: rootDirectory,
                at: configPath
            )
            cachedConfigs[path] = config
            return config
        }

        func locateConfig(at path: AbsolutePath) async throws -> AbsolutePath? {
            if let rootDirectoryPath = try await rootDirectoryLocator.locate(from: path) {
                for candidate in [
                    rootDirectoryPath
                        .appending(
                            // swiftlint:disable:next force_try
                            try! RelativePath(validating: "\(Constants.tuistDirectoryName)/Config.swift")
                        ),
                    // swiftlint:disable:next force_try
                    rootDirectoryPath.appending(try! RelativePath(validating: Constants.tuistManifestFileName)),
                ] {
                    if try await fileSystem.exists(candidate) {
                        return candidate
                    }
                }
            }
            return nil
        }

        private func defaultConfig(at path: AbsolutePath) async throws -> TuistConfig.Tuist {
            let anyXcodeProjectOrWorkspace = !(
                try await fileSystem.glob(directory: path, include: ["*.xcodeproj", "*.xcworkspace"])
                    .collect().isEmpty
            )
            let anyWorkspaceOrProjectManifest = !(try await fileSystem.glob(
                directory: path,
                include: ["Project.swift", "Workspace.swift"]
            ).collect().isEmpty)

            let anyPackageSwift = !(
                try await fileSystem.glob(directory: path, include: ["Package.swift"])
                    .collect().isEmpty
            )

            if anyPackageSwift, !anyWorkspaceOrProjectManifest {
                return TuistConfig.Tuist(
                    project: .swiftPackage(TuistSwiftPackageOptions()),
                    fullHandle: nil,
                    inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
                    url: Constants.URLs.production
                )
            } else if anyXcodeProjectOrWorkspace, !anyWorkspaceOrProjectManifest {
                return TuistConfig.Tuist(
                    project: .xcode(TuistXcodeProjectOptions()),
                    fullHandle: nil,
                    inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
                    url: Constants.URLs.production
                )
            } else {
                return TuistConfig.Tuist.default
            }
        }
    }
#endif
