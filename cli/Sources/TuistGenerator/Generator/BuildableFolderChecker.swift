import FileSystem
import Mockable
import XcodeGraph

@Mockable
public protocol BuildableFolderChecking {
    func containsResources(_ folders: [XcodeGraph.BuildableFolder]) async throws -> Bool
    func containsSources(_ folders: [XcodeGraph.BuildableFolder]) async throws -> Bool
}

public struct BuildableFolderChecker: BuildableFolderChecking {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func containsSources(_ folders: [XcodeGraph.BuildableFolder]) async throws -> Bool {
        for folder in folders {
            if !(try await fileSystem.glob(directory: folder.path, include: Target.validSourceExtensions.map { "**/*.\($0)" })
                .collect().isEmpty
            ) {
                return true
            }
        }
        return false
    }

    public func containsResources(_ folders: [XcodeGraph.BuildableFolder]) async throws -> Bool {
        for folder in folders {
            if !(try await fileSystem.glob(directory: folder.path, include: Target.validResourceExtensions.map { "**/*.\($0)" })
                .collect().isEmpty
            ) {
                return true
            }
        }
        return false
    }
}
