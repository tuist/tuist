#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

import Foundation
import Path

public enum POSIXDirectory {
    /// Idempotently ensures a directory exists at `path`. Equivalent to
    /// `mkdir -p` for the leaf component: a single `mkdir(2)` call that
    /// treats `EEXIST` as success — safe under concurrent processes
    /// racing to create the same directory.
    public static func ensureExists(_ path: AbsolutePath, mode: mode_t = 0o755) throws {
        let result = path.pathString.withCString { mkdir($0, mode) }
        if result != 0, errno != EEXIST {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "mkdir(\(path.pathString)) failed (errno \(errno))"]
            )
        }
    }
}
