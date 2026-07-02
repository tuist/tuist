import FileSystem
import Foundation
import Path

extension SwiftPackageManagerWorkspaceState {
    /// The dependency kinds SwiftPM uses for local (path-based) packages across Swift versions.
    public static func isLocalDependencyKind(_ kind: String) -> Bool {
        ["local", "fileSystem", "localSourceControl"].contains(kind)
    }

    /// Strips control characters and aligns `/private/var` with `/var` so paths encoded in
    /// `workspace-state.json` resolve correctly relative to a scratch directory.
    public static func sanitizedPath(_ path: String) -> String {
        String(path.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .replacingOccurrences(of: "/private/var", with: "/var")
    }

    /// Decodes the `workspace-state.json` file in the given scratch directory, or `nil` when absent.
    public static func load(
        from scratchDirectory: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> SwiftPackageManagerWorkspaceState? {
        let workspaceStatePath = scratchDirectory.appending(component: "workspace-state.json")
        guard try await fileSystem.exists(workspaceStatePath) else {
            return nil
        }
        return try JSONDecoder().decode(
            SwiftPackageManagerWorkspaceState.self,
            from: try await fileSystem.readFile(at: workspaceStatePath)
        )
    }
}

extension SwiftPackageManagerWorkspaceState.Dependency {
    /// The absolute path to a local package dependency's folder, resolved relative to `scratchDirectory`.
    public func localPackageFolder(relativeTo scratchDirectory: AbsolutePath) -> AbsolutePath? {
        // Depending on the Swift version, the path is available either in `path` or in `location`.
        guard let path = packageRef.path ?? packageRef.location else {
            return nil
        }
        return try? AbsolutePath(
            validating: SwiftPackageManagerWorkspaceState.sanitizedPath(path),
            relativeTo: scratchDirectory
        )
    }
}
