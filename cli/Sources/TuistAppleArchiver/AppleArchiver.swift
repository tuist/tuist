import AppleArchive
import Foundation
import Mockable
import Path
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
        let source = FilePath(directory.pathString)
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

        // Exclude SLC (symlink content) and LNK (link) so symlinks are
        // dereferenced during compression. Otherwise, both the symlink and its
        // target end up in the archive, causing EEXIST errors during extraction.
        let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,UID,GID,MOD,FLG,MTM,CTM")!

        let filter: ArchiveHeader.EntryFilter = { _, path, _ in
            let pathString = path.string
            if excludePatterns.contains(where: { pathString.contains($0) }) {
                return .skip
            }
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
        do {
            try extract(from: archive, to: directory)
        } catch {
            // Apple Archive's writeDirectoryContents may produce duplicate entries
            // when the source directory contains symlinks to sibling directories.
            // The extractor fails with EEXIST (renamex_np) on the second entry.
            // Clear the partially-extracted contents and retry; the duplicate
            // entries are identical so last-write-wins is safe.
            guard error.localizedDescription.contains("File exists") else { throw error }
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(atPath: directory.pathString) {
                for item in contents {
                    try? fm.removeItem(atPath: "\(directory.pathString)/\(item)")
                }
            }
            try extract(from: archive, to: directory)
        }
    }

    private func extract(from archive: AbsolutePath, to directory: AbsolutePath) throws {
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
