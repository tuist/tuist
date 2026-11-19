import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Directory trees a restore replaces, such as the private copies `NativeWorkspace` made.
/// Deleting a tree costs a metadata operation per file, which on large graphs dominates the
/// install that follows a native run. Renaming it into the scratch directory's trash is a single
/// operation, and a detached process deletes the trash after the restore.
struct ScratchTrash: Sendable {
    static let directoryName = ".swifterpm-trash"

    let directory: URL

    init(scratchDir: URL) {
        directory = scratchDir.appendingPathComponent(Self.directoryName)
    }

    /// Removes the item at `url`. Symlinks and files are removed in place; directories move into
    /// the trash, or are deleted in place when they live on another volume.
    func discard(_ url: URL) async throws {
        guard fileSystem.existsIncludingSymlinks(url) else { return }
        guard fileSystem.isDirectoryAndNotSymlink(url) else {
            try await fileSystem.removePath(url)
            return
        }
        try await fileSystem.makeDirectory(at: directory.absolutePath, options: [.createTargetParentDirectories])
        let destination = directory.appendingPathComponent(UUID().uuidString)
        let result = url.path.withCString { source in
            destination.path.withCString { rename(source, $0) }
        }
        if result != 0 {
            try await fileSystem.removePath(url)
        }
    }

    /// Starts deleting everything in the trash, including entries an interrupted purge left
    /// behind, and returns without waiting for it to finish.
    func purge() async {
        guard fileSystem.isDirectoryAndNotSymlink(directory),
              let entries = try? await fileSystem.contentsOfDirectory(at: directory),
              !entries.isEmpty
        else { return }
        await SystemProcess.spawnDetached("/bin/rm", ["-rf", "--"] + entries.map(\.path))
    }
}
