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
            if folder.resolvedFiles.contains(where: { Target.validSourceExtensions.contains($0.path.extension ?? "") }) {
                return true
            }
        }
        return false
    }

    public func containsResources(_ folders: [XcodeGraph.BuildableFolder]) async throws -> Bool {
        let extensions = Target.validResourceExtensions + Target.validResourceCompatibleFolderExtensions
        for folder in folders {
            if folder.resolvedFiles.contains(where: { extensions.contains($0.path.extension ?? "") }) {
                return true
            }
        }
        return false
    }
}
