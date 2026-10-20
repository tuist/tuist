import Foundation
import Path

/// A point-in-time reading of the volume that backs a path.
public struct VolumeSpace: Equatable, Sendable {
    /// Bytes still writable on the volume.
    public let freeBytes: Int64
    /// The volume's total size.
    public let totalBytes: Int64

    public init(freeBytes: Int64, totalBytes: Int64) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }

    /// Reads the free and total space of the volume backing `path`, walking up to the nearest existing
    /// ancestor so a path a failed build never got to create still reports the volume it would have used.
    ///
    /// Deliberately `statfs`-based (`systemFreeSize`) rather than
    /// `volumeAvailableCapacityForImportantUsageKey`: the latter counts space macOS would have to purge
    /// first, so it reports capacity a build cannot actually write and would describe a volume that has
    /// just failed with `ENOSPC` as having gigabytes to spare.
    public static func read(at path: AbsolutePath) -> VolumeSpace? {
        var candidate: AbsolutePath? = path
        while let current = candidate {
            if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: current.pathString),
               let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value,
               let total = (attributes[.systemSize] as? NSNumber)?.int64Value
            {
                return VolumeSpace(freeBytes: free, totalBytes: total)
            }
            candidate = current.isRoot ? nil : current.parentDirectory
        }
        return nil
    }

    /// Whether the volume has so little room left that a build failure is more likely to be the disk than
    /// the code. A build that failed on a healthy volume leaves far more than this behind; one that failed
    /// because the volume filled is sitting on tens of megabytes, since the writes that did not fit were
    /// the last ones attempted.
    public var isExhausted: Bool {
        freeBytes < VolumeSpace.exhaustionThresholdBytes
    }

    static let exhaustionThresholdBytes: Int64 = 512 * 1024 * 1024

    public var formattedFreeSpace: String {
        let free = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(free) free of \(total)"
    }
}
