import FileSystem
import Mockable
import Path
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
            if folder.resolvedFiles.first(where: { Target.validSourceExtensions.contains($0.path.extension ?? "") }) != nil {
                return true
            }
        }
        return false
    }

    public func containsResources(_ folders: [XcodeGraph.BuildableFolder]) async throws -> Bool {
        for folder in folders {
            if folder.resolvedFiles.first(where: { Target.validResourceExtensions.contains($0.path.extension ?? "") }) != nil {
                return true
            }
        }
        return false
    }
}
