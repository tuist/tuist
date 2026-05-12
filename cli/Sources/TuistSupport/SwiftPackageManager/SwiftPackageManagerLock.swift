import Path
import TSCBasic
import TuistLogging

public struct SwiftPackageManagerLock: Sendable {
    public init() {}

    public func withLock<T>(
        scratchDirectory: Path.AbsolutePath,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let fileLock = try TSCBasic.FileLock.prepareLock(
            fileToLock: try TSCBasic.AbsolutePath(validating: scratchDirectory.pathString)
        )
        Logger.current.debug("Waiting for Swift Package Manager lock at \(scratchDirectory.pathString)")

        return try await fileLock.withLock(type: .exclusive) {
            Logger.current.debug("Acquired Swift Package Manager lock at \(scratchDirectory.pathString)")
            return try await operation()
        }
    }
}
