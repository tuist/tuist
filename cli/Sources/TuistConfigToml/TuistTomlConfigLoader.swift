import FileSystem
import Foundation
import Mockable
import Path
import TOMLDecoder
import TuistConstants
import TuistRootDirectoryLocator

@Mockable
public protocol TuistTomlConfigLoading: Sendable {
    func loadConfig(at path: AbsolutePath) async throws -> TuistTomlConfig?
}

public struct TuistTomlConfigLoader: TuistTomlConfigLoading {
    private let fileSystem: FileSysteming
    private let rootDirectoryLocator: RootDirectoryLocating

    public init(
        fileSystem: FileSysteming = FileSystem(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.fileSystem = fileSystem
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func loadConfig(at path: AbsolutePath) async throws -> TuistTomlConfig? {
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
}
