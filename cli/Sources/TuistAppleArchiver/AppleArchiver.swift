import AppleArchive
import Foundation
import Mockable
import Path
import Synchronization
import System

public enum AppleArchiverError: LocalizedError, Equatable {
    case compressionFailed(String)
    case decompressionFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .compressionFailed(detail):
            return "Failed to compress archive: \(detail)"
        case let .decompressionFailed(detail):
            return "Failed to decompress archive: \(detail)"
        }
    }
}

@Mockable
public protocol AppleArchiving {
    func compress(
        directory: AbsolutePath,
        to archivePath: AbsolutePath,
        excludePatterns: [String],
        preservesBaseDirectory: Bool
    ) async throws
    func compress(
        subdirectory: AbsolutePath,
        relativeTo baseDirectory: AbsolutePath,
        to archivePath: AbsolutePath
    ) async throws
    func decompress(archive: AbsolutePath, to directory: AbsolutePath) async throws
}

extension AppleArchiving {
    public func compress(
        directory: AbsolutePath,
        to archivePath: AbsolutePath,
        excludePatterns: [String]
    ) async throws {
        try await compress(
            directory: directory,
            to: archivePath,
            excludePatterns: excludePatterns,
            preservesBaseDirectory: false
        )
    }
}

public struct AppleArchiver: AppleArchiving {
    public init() {}

    /// - Parameter preservesBaseDirectory: When `true`, archive entries are
    ///   prefixed with `directory.basename`, so extractors land at
    ///   `destination/<bundleName>/…`. This matters for `.xcresult` and
    ///   `.xctestproducts` payloads consumed by Xcode or the server-side
    ///   xcresult processor — the wrapping directory is part of the bundle's
    ///   identity. Defaults to `false` to keep the lighter-weight behavior of
    ///   archiving the directory's contents flat for callers that don't need
    ///   the wrapper (sharding test products, etc.).
    public func compress(
        directory: AbsolutePath,
        to archivePath: AbsolutePath,
        excludePatterns: [String] = [],
        preservesBaseDirectory: Bool = false
    ) async throws {
        // When the bundle directory must be preserved, archive from the parent
        // so the bundle's basename appears in entry paths, and prune siblings
        // via the entry filter. Otherwise archive the contents directly.
        let source: FilePath
        let bundleScope: (name: String, prefix: String)?
        if preservesBaseDirectory {
            source = FilePath(directory.parentDirectory.pathString)
            bundleScope = (name: directory.basename, prefix: "\(directory.basename)/")
        } else {
            source = FilePath(directory.pathString)
            bundleScope = nil
        }
        // writeDirectoryContents may visit the same file twice when the source
        // directory contains symlinks to sibling directories. Track seen paths
        // and skip duplicates to prevent EEXIST errors during extraction.
        let seenPaths = Mutex(Set<String>())
        let filter: ArchiveHeader.EntryFilter = { _, path, _ in
            let pathString = path.string
            // When preserving the base directory, prune siblings of the target
            // bundle so only the bundle subtree is archived. Returning `.skip`
            // on a directory header also prunes its descendants, so this is
            // cheap even if the parent directory holds unrelated content.
            let scopedRelativePath: String?
            if let bundleScope {
                if pathString == bundleScope.name {
                    scopedRelativePath = ""
                } else if pathString.hasPrefix(bundleScope.prefix) {
                    scopedRelativePath = String(pathString.dropFirst(bundleScope.prefix.count))
                } else {
                    return .skip
                }
            } else {
                scopedRelativePath = pathString
            }
            // Match exclude patterns against the path within the bundle so a
            // caller-provided pattern can't match the bundle's own basename.
            if let scopedRelativePath, !scopedRelativePath.isEmpty,
               excludePatterns.contains(where: { scopedRelativePath.contains($0) })
            {
                return .skip
            }
            let inserted = seenPaths.withLock { $0.insert(pathString).inserted }
            guard inserted else { return .skip }
            return .ok
        }

        try writeArchive(from: source, to: archivePath, filter: filter)
    }

    /// Archives the subtree rooted at `subdirectory` (which must live inside
    /// `baseDirectory`), writing entry paths relative to `baseDirectory` so the
    /// subtree's full relative path is preserved. Extracting the archive into a
    /// directory reconstructs `subdirectory` at its original location.
    ///
    /// Unlike staging the subtree into a temporary directory and archiving that,
    /// this reads the files in place — no copy of the payload is made. Sharding
    /// uses it to split a large `.xctestproducts` bundle into one archive per
    /// `.xctest` without duplicating gigabytes of test binaries on disk.
    public func compress(
        subdirectory: AbsolutePath,
        relativeTo baseDirectory: AbsolutePath,
        to archivePath: AbsolutePath
    ) async throws {
        let relativePath = subdirectory.relative(to: baseDirectory).pathString

        // writeDirectoryContents may visit the same file twice when the source
        // directory contains symlinks to sibling directories. Track seen paths
        // and skip duplicates to prevent EEXIST errors during extraction.
        let seenPaths = Mutex(Set<String>())
        let filter: ArchiveHeader.EntryFilter = { _, path, _ in
            let pathString = path.string
            // Keep the target subtree plus the ancestor directories leading down
            // to it (so the walk descends that far) and prune everything else.
            // `.skip` on a directory header also prunes its descendants, so the
            // sibling bundles in the same products directory are never read.
            let isWithinTarget = pathString == relativePath || pathString.hasPrefix("\(relativePath)/")
            let isAncestor = relativePath.hasPrefix("\(pathString)/")
            guard isWithinTarget || isAncestor else { return .skip }
            let inserted = seenPaths.withLock { $0.insert(pathString).inserted }
            guard inserted else { return .skip }
            return .ok
        }

        try writeArchive(from: FilePath(baseDirectory.pathString), to: archivePath, filter: filter)
    }

    private func writeArchive(
        from source: FilePath,
        to archivePath: AbsolutePath,
        filter: @escaping ArchiveHeader.EntryFilter
    ) throws {
        let destination = FilePath(archivePath.pathString)

        guard let writeStream = ArchiveByteStream.fileStream(
            path: destination,
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: [.ownerReadWrite, .groupRead, .otherRead]
        ) else {
            throw AppleArchiverError.compressionFailed("could not create file stream")
        }
        defer { try? writeStream.close() }

        guard let compressStream = ArchiveByteStream.compressionStream(
            using: .lzfse,
            writingTo: writeStream
        ) else {
            throw AppleArchiverError.compressionFailed("could not create compression stream")
        }
        defer { try? compressStream.close() }

        guard let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream) else {
            throw AppleArchiverError.compressionFailed("could not create encode stream")
        }
        defer { try? encodeStream.close() }

        let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,UID,GID,MOD,FLG,MTM,CTM,SLC,LNK")!
        try encodeStream.writeDirectoryContents(
            archiveFrom: source,
            keySet: keySet,
            selectUsing: filter
        )

        try encodeStream.close()
        try compressStream.close()
        try writeStream.close()
    }

    public func decompress(archive: AbsolutePath, to directory: AbsolutePath) async throws {
        let source = FilePath(archive.pathString)
        let destination = FilePath(directory.pathString)

        guard let readStream = ArchiveByteStream.fileStream(
            path: source,
            mode: .readOnly,
            options: [],
            permissions: []
        ) else {
            throw AppleArchiverError.decompressionFailed("could not open archive")
        }
        defer { try? readStream.close() }

        guard let decompressStream = ArchiveByteStream.decompressionStream(
            readingFrom: readStream
        ) else {
            throw AppleArchiverError.decompressionFailed("could not create decompression stream")
        }
        defer { try? decompressStream.close() }

        guard let decodeStream = ArchiveStream.decodeStream(
            readingFrom: decompressStream
        ) else {
            throw AppleArchiverError.decompressionFailed("could not create decode stream")
        }
        defer { try? decodeStream.close() }

        guard let extractStream = ArchiveStream.extractStream(
            extractingTo: destination,
            flags: [.ignoreOperationNotPermitted]
        ) else {
            throw AppleArchiverError.decompressionFailed("could not create extract stream")
        }
        defer { try? extractStream.close() }

        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)

        try extractStream.close()
        try decodeStream.close()
        try decompressStream.close()
        try readStream.close()
    }
}
