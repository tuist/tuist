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
        excludePatterns: [String]
    ) async throws
    func decompress(archive: AbsolutePath, to directory: AbsolutePath) async throws
}

public struct AppleArchiver: AppleArchiving {
    public init() {}

    public func compress(
        directory: AbsolutePath,
        to archivePath: AbsolutePath,
        excludePatterns: [String] = []
    ) async throws {
        // Archive from the parent so the bundle's basename is preserved in the
        // archive entries. Extractors land at `destination/<bundleName>/…`, which
        // is what Xcode and the server-side xcresult processor expect for
        // `.xcresult` and `.xctestproducts` bundles.
        let source = FilePath(directory.parentDirectory.pathString)
        let destination = FilePath(archivePath.pathString)
        let bundleName = directory.basename
        let bundleDirectoryPrefix = "\(bundleName)/"

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

        // writeDirectoryContents may visit the same file twice when the source
        // directory contains symlinks to sibling directories. Track seen paths
        // and skip duplicates to prevent EEXIST errors during extraction.
        let seenPaths = Mutex(Set<String>())
        let filter: ArchiveHeader.EntryFilter = { _, path, _ in
            let pathString = path.string
            // Prune siblings of the target bundle so only the bundle subtree
            // is archived. Returning `.skip` on a directory header also prunes
            // its descendants, so this is cheap even if the parent directory
            // holds unrelated content.
            let relativePath: String
            if pathString == bundleName {
                relativePath = ""
            } else if pathString.hasPrefix(bundleDirectoryPrefix) {
                relativePath = String(pathString.dropFirst(bundleDirectoryPrefix.count))
            } else {
                return .skip
            }
            // Match exclude patterns against the path *within* the bundle so a
            // caller-provided pattern can't accidentally match the bundle name.
            if !relativePath.isEmpty,
               excludePatterns.contains(where: { relativePath.contains($0) })
            {
                return .skip
            }
            let inserted = seenPaths.withLock { $0.insert(pathString).inserted }
            guard inserted else { return .skip }
            return .ok
        }
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
