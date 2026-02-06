import FileSystem
import Foundation
import Mockable
import Path
import TOMLDecoder
import TuistConstants

@Mockable
public protocol TuistTomlConfigLoading: Sendable {
    func loadConfig(at path: AbsolutePath) async throws -> TuistTomlConfig?
}

public final class TuistTomlConfigLoader: TuistTomlConfigLoading {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func loadConfig(at path: AbsolutePath) async throws -> TuistTomlConfig? {
        guard let tomlPath = try await locateTomlConfig(from: path) else {
            return nil
        }
        let tomlString = try await fileSystem.readTextFile(at: tomlPath)
        let decoder = TOMLDecoder()
        return try decoder.decode(TuistTomlConfig.self, from: tomlString)
    }

    private func locateTomlConfig(from path: AbsolutePath) async throws -> AbsolutePath? {
        var currentPath = path

        while true {
            let candidate = currentPath.appending(component: Constants.tuistTomlFileName)
            if try await fileSystem.exists(candidate, isDirectory: false) {
                return candidate
            }
            if currentPath.isRoot {
                break
            }
            currentPath = currentPath.parentDirectory
        }
        return nil
    }
}
