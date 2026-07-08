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
    func decompress(archive: AbsolutePath, to directory: AbsolutePath) async throws
    func decompress(data: Data, to directory: AbsolutePath) async throws
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

        guard let readStream = ArchiveByteStream.fileStream(
            path: source,
            mode: .readOnly,
            options: [],
            permissions: []
        ) else {
            throw AppleArchiverError.decompressionFailed("could not open archive")
        }
        defer { try? readStream.close() }

        try extract(from: readStream, to: FilePath(directory.pathString))

        try readStream.close()
    }

    /// Decompresses an archive held in memory, without materializing it as a
    /// temporary file first. Used by the module-cache pull, where the artifact
    /// arrives as `Data` from the download and writing it to disk only to read
    /// it straight back is wasted I/O.
    public func decompress(data: Data, to directory: AbsolutePath) async throws {
        let instance = DataReadStream(data: data)
        guard let readStream = ArchiveByteStream.customStream(instance: instance) else {
            throw AppleArchiverError.decompressionFailed("could not create memory stream")
        }
        defer { try? readStream.close() }

        try extract(from: readStream, to: FilePath(directory.pathString))

        try readStream.close()
    }

    private func extract(from readStream: ArchiveByteStream, to destination: FilePath) throws {
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
    }
}

/// A read-only `ArchiveByteStream` backed by an in-memory buffer.
private final class DataReadStream: ArchiveByteStreamProtocol {
    private let data: Data
    private var position: Int64 = 0

    init(data: Data) {
        self.data = data
    }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        let count = min(buffer.count, data.count - Int(position))
        if count <= 0 { return 0 }
        data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            buffer.baseAddress!.copyMemory(
                from: source.baseAddress!.advanced(by: Int(position)),
                byteCount: count
            )
        }
        position += Int64(count)
        return count
    }

    func read(into buffer: UnsafeMutableRawBufferPointer, atOffset offset: Int64) throws -> Int {
        let count = min(buffer.count, data.count - Int(offset))
        if count <= 0 { return 0 }
        data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            buffer.baseAddress!.copyMemory(
                from: source.baseAddress!.advanced(by: Int(offset)),
                byteCount: count
            )
        }
        return count
    }

    func write(from _: UnsafeRawBufferPointer) throws -> Int {
        throw AppleArchiverError.decompressionFailed("memory stream is read-only")
    }

    func write(from _: UnsafeRawBufferPointer, atOffset _: Int64) throws -> Int {
        throw AppleArchiverError.decompressionFailed("memory stream is read-only")
    }

    func seek(toOffset offset: Int64, relativeTo origin: FileDescriptor.SeekOrigin) throws -> Int64 {
        switch origin {
        case .start: position = offset
        case .current: position += offset
        case .end: position = Int64(data.count) + offset
        default: throw AppleArchiverError.decompressionFailed("unsupported seek origin")
        }
        return position
    }

    func cancel() {}

    func close() throws {}
}
