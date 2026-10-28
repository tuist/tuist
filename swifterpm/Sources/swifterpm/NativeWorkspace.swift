import Foundation

/// Native SwiftPM owns mutable working copies, never aliases into the shared source cache.
/// Keep preparation and the process under the same scratch lock; source restoration takes
/// that lock separately after the native process has finished.
enum NativeWorkspace {
    static func prepare(scratchDir: URL) async throws -> Set<String> {
        var ownedCheckouts = Set<String>()
        let checkouts = scratchDir.appendingPathComponent("checkouts")
        if try await fileSystem.exists(checkouts.absolutePath) {
            for checkout in try await fileSystem.contentsOfDirectory(at: checkouts) {
                if fileSystem.isSymlink(checkout) {
                    if fileSystem.existsIncludingSymlinks(checkout.appendingPathComponent(".git")) {
                        try await fileSystem.removePath(checkout)
                    } else {
                        try await privatize(checkout)
                    }
                    ownedCheckouts.insert(checkout.lastPathComponent)
                }
            }
        }
        let artifacts = scratchDir.appendingPathComponent("artifacts")
        if try await fileSystem.exists(artifacts.absolutePath) {
            for package in try await fileSystem.contentsOfDirectory(at: artifacts)
                where fileSystem.isDirectoryAndNotSymlink(package)
            {
                for artifact in try await fileSystem.contentsOfDirectory(at: package)
                    where fileSystem.isSymlink(artifact)
                {
                    try await privatize(artifact)
                }
            }
        }
        return ownedCheckouts
    }

    private static func privatize(_ link: URL) async throws {
        let source = link.resolvingSymlinksInPath()
        guard try await fileSystem.exists(source.absolutePath) else {
            try await fileSystem.removePath(link)
            return
        }
        let staging = try await fileSystem.temporaryDirectory(in: link.deletingLastPathComponent())
        do {
            try await fileSystem.removePath(staging)
            try await fileSystem.copyPrivately(source: source, destination: staging)
            try await fileSystem.replaceWithStagedItem(source: staging, destination: link)
        } catch {
            try? await fileSystem.removePath(staging)
            throw error
        }
    }
}

extension SwifterPM {
    /// Use when delegating directly to native SwiftPM, including when SwifterPM is disabled.
    public func withNativeWorkspace<T>(
        packageDirectory: URL,
        scratchDirectory: URL? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        let scratch = scratchDirectory ?? packageDirectory.appendingPathComponent(".build")
        let lock = try await PathLock.acquire(at: scratch.appendingPathComponent(".swifterpm.lock"))
        defer { withExtendedLifetime(lock) {} }
        _ = try await NativeWorkspace.prepare(scratchDir: scratch)
        return try await operation()
    }
}
