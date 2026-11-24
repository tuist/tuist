import FileSystem
import Foundation
import Mockable
import Path
import TOMLDecoder
import TuistConstants
import TuistRootDirectoryLocator

@Mockable
protocol TuistTomlConfigLoading: Sendable {
    func loadConfig(at path: AbsolutePath) async throws -> TuistTomlConfig?
    func loadCargoManifestConfig(at path: AbsolutePath) async throws -> TuistTomlConfig?
}

/// The parts of a `Cargo.toml` that hold Tuist's configuration. Cargo ignores `metadata` tables, without warning.
private struct CargoManifest: Decodable {
    struct Section: Decodable {
        struct Metadata: Decodable {
            let tuist: TuistTomlConfig?
        }

        let metadata: Metadata?
    }

    let workspace: Section?
    let package: Section?
}

struct TuistTomlConfigLoader: TuistTomlConfigLoading {
    private let fileSystem: FileSysteming
    private let rootDirectoryLocator: RootDirectoryLocating

    init(
        fileSystem: FileSysteming = FileSystem(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.fileSystem = fileSystem
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    func loadConfig(at path: AbsolutePath) async throws -> TuistTomlConfig? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: path) else {
            return nil
        }
        let tomlPath = rootDirectory.appending(component: Constants.tuistTomlFileName)
        guard try await fileSystem.exists(tomlPath, isDirectory: false) else {
            return nil
        }
        let tomlString = try await fileSystem.readTextFile(at: tomlPath)
        let decoder = TOMLDecoder()
        return try decoder.decode(TuistTomlConfig.self, from: tomlString)
    }

    /// `[workspace.metadata.tuist]` or `[package.metadata.tuist]` of the manifest Cargo treats as the root: the
    /// nearest ancestor `Cargo.toml` with a `[workspace]` table, or else the nearest `Cargo.toml`.
    func loadCargoManifestConfig(at path: AbsolutePath) async throws -> TuistTomlConfig? {
        var nearest: CargoManifest?
        var directory = path
        while true {
            let manifestPath = directory.appending(component: "Cargo.toml")
            if try await fileSystem.exists(manifestPath, isDirectory: false) {
                let manifest = try TOMLDecoder().decode(
                    CargoManifest.self, from: try await fileSystem.readTextFile(at: manifestPath)
                )
                if manifest.workspace != nil {
                    return manifest.workspace?.metadata?.tuist ?? manifest.package?.metadata?.tuist
                }
                nearest = nearest ?? manifest
            }
            if directory.isRoot { break }
            directory = directory.parentDirectory
        }
        return nearest?.package?.metadata?.tuist
    }
}
