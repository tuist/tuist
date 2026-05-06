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
        folders.contains(where: { folder in
            folder.resolvedFiles.contains(where: { Target.validSourceExtensions.contains($0.path.extension ?? "") })
        })
    }

    public func containsResources(_ folders: [XcodeGraph.BuildableFolder]) async throws -> Bool {
        // Mirrors Xcode's synchronized-folder behavior: any file that is not a known source / header
        // is routed to a resource build rule (CpResource by default), so we treat it as a resource.
        let sourceExtensions = Set(
            Target.validSourceExtensions
                + Target.validSourceCompatibleFolderExtensions
                + Target.validHeaderExtensions
        )
        return folders.contains(where: { folder in
            folder.resolvedFiles.contains(where: { !sourceExtensions.contains($0.path.extension ?? "") })
        })
    }
}
