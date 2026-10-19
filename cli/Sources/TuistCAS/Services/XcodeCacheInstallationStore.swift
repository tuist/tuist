#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
import FileSystem
import Foundation
import Mockable
import Path
import struct TSCUtility.Version
import TuistEnvironment

@Mockable
public protocol XcodeCacheInstallationStoring {
    /// Advances a usable target, or repairs an unavailable installation.
    /// Returns whether this installation is selected, not whether it is running.
    /// Generation uses `onlyIfInstalled` so it cannot install a service.
    func update(executable: AbsolutePath, tuistVersion: String, onlyIfInstalled: Bool) async throws -> Bool
    func invalidate() async throws
}

/// Owns the stable launch entry point, version selection, and unavailable-target recovery.
public struct XcodeCacheInstallationStore: XcodeCacheInstallationStoring, Sendable {
    struct Target: Codable {
        let executable: AbsolutePath
        let tuistVersion: String
        var highestTuistVersion: String?
    }

    private let fileSystem: FileSysteming
    private let directory: AbsolutePath
    private var targetPath: AbsolutePath { directory.appending(component: "cas-launch-target.json") }
    private var launcherPath: AbsolutePath { directory.appending(component: "cas-launcher.sh") }

    public init(fileSystem: FileSysteming = FileSystem(), directory: AbsolutePath? = nil) {
        self.fileSystem = fileSystem
        self.directory = directory ?? Environment.current.casPluginInstallPath().parentDirectory
    }

    public func update(executable: AbsolutePath, tuistVersion: String, onlyIfInstalled: Bool) async throws -> Bool {
        // Do not create even a lock file when generation encounters an unconfigured machine.
        if onlyIfInstalled, try await !fileSystem.exists(launcherPath) { return false }
        guard let version = try? Version(versionString: tuistVersion) else {
            throw XcodeCacheInstallationStoreError.invalidVersion(tuistVersion)
        }
        try await fileSystem.makeDirectory(at: directory)
        return try await withLock {
            if onlyIfInstalled, try await !fileSystem.exists(launcherPath) { return false }
            if !onlyIfInstalled, try await !fileSystem.exists(launcherPath) {
                try await fileSystem.writeText(Self.launcher, at: launcherPath)
            }
            if try await fileSystem.exists(targetPath) {
                // A corrupt pointer is an error, not permission to silently downgrade it.
                let target: Target = try await fileSystem.readJSONFile(at: targetPath)
                let installedVersion = try Version(versionString: target.highestTuistVersion ?? target.tuistVersion)
                if try await isUsable(target.executable) {
                    if installedVersion > version { return false }
                    if installedVersion == version {
                        guard try await isUsable(executable) else { return false }
                        guard try await canonicalPath(target.executable) == canonicalPath(executable) else { return false }
                        if target.tuistVersion == tuistVersion { return true }
                    }
                }
            }
            guard try await isUsable(executable) else {
                throw XcodeCacheInstallationStoreError.missingExecutable(executable)
            }
            // Keep stable aliases usable after a package manager removes the old
            // versioned directory. Canonical paths are only for identity checks.
            try await fileSystem.writeAsJSON(Target(executable: executable, tuistVersion: tuistVersion), at: targetPath)
            return true
        }
    }

    private func isUsable(_ path: AbsolutePath) async throws -> Bool {
        try await fileSystem.exists(path, isDirectory: false) && access(path.pathString, X_OK) == 0
    }

    private func canonicalPath(_ path: AbsolutePath, remainingLinks: Int = 40) async throws -> AbsolutePath {
        guard path != path.parentDirectory else { return path }
        guard remainingLinks > 0 else { throw XcodeCacheInstallationStoreError.missingExecutable(path) }
        let parent = try await canonicalPath(path.parentDirectory, remainingLinks: remainingLinks)
        let candidate = parent.appending(component: path.basename)
        let resolved = try await fileSystem.resolveSymbolicLink(candidate)
        if resolved != candidate {
            return try await canonicalPath(resolved, remainingLinks: remainingLinks - 1)
        }
        return candidate
    }

    public func invalidate() async throws {
        guard try await fileSystem.exists(directory) else { return }
        try await withLock {
            // Remove the entry point first so concurrent generation cannot recreate the target.
            try await fileSystem.remove(launcherPath)
            try await fileSystem.remove(targetPath)
            try await fileSystem.remove(directory.appending(component: "cas-install.json"))
        }
    }

    private func withLock<T>(_ body: () async throws -> T) async throws -> T {
        let lockPath = directory.appending(component: "cas-launcher.lock")
        let descriptor = open(lockPath.pathString, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw XcodeCacheInstallationStoreError.lockFailed(errno) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else {
                throw XcodeCacheInstallationStoreError.lockFailed(errno)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        return try await body()
    }

    /// launchd executes /bin/sh, not a version-manager shim or the setup-time CLI.
    /// Keep arguments and credentials in launchd; the pointer contains no tokens.
    static let launcher = """
    #!/bin/sh
    set -eu
    target=$1
    shift
    executable=$(/usr/bin/plutil -extract executable raw -o - "$target")
    export TUIST_CAS_PROXY_LAUNCH_TARGET="$target"
    exec "$executable" "$@"
    """
}

enum XcodeCacheInstallationStoreError: Error, Equatable {
    case invalidVersion(String)
    case missingExecutable(AbsolutePath)
    case lockFailed(Int32)
}
