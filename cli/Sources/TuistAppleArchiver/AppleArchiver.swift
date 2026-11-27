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
    func compress(
        subdirectories: [AbsolutePath],
        relativeTo baseDirectory: AbsolutePath,
        to archivePath: AbsolutePath
    ) async throws
    func decompress(archive: AbsolutePath, to directory: AbsolutePath) async throws
    /// Extracts an archive as its bytes arrive, so a download and its extraction overlap. Returns the archive's
    /// size. A failure of `chunks` is rethrown in preference to the extraction failure it causes.
    @discardableResult
    func decompress(chunks: AsyncThrowingStream<Data, Error>, to directory: AbsolutePath) async throws -> Int64
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
               excludePatterns.contains(where: { Self.matchesExcludePattern($0, path: scopedRelativePath) })
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
        try await compress(subdirectories: [subdirectory], relativeTo: baseDirectory, to: archivePath)
    }

    public func compress(
        subdirectories: [AbsolutePath],
        relativeTo baseDirectory: AbsolutePath,
        to archivePath: AbsolutePath
    ) async throws {
        let relativePaths = subdirectories
            .map { $0.relative(to: baseDirectory).pathString }
            .sorted()

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
            let isWithinTarget = relativePaths.contains { relativePath in
                pathString == relativePath || pathString.hasPrefix("\(relativePath)/")
            }
            let isAncestor = relativePaths.contains { $0.hasPrefix("\(pathString)/") }
            guard isWithinTarget || isAncestor else { return .skip }
            let inserted = seenPaths.withLock { $0.insert(pathString).inserted }
            guard inserted else { return .skip }
            return .ok
        }

        try writeArchive(from: FilePath(baseDirectory.pathString), to: archivePath, filter: filter)
    }

    private static func matchesExcludePattern(_ pattern: String, path: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        if path.contains(pattern) { return true }
        guard pattern.hasSuffix("/") else { return false }

        let directoryPattern = String(pattern.dropLast())
        guard !directoryPattern.isEmpty else { return false }
        return path.hasSuffix(directoryPattern)
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
        guard let readStream = ArchiveByteStream.fileStream(
            path: FilePath(archive.pathString),
            mode: .readOnly,
            options: [],
            permissions: []
        ) else {
            throw AppleArchiverError.decompressionFailed("could not open archive")
        }
        try Self.extract(readStream, to: directory)
    }

    @discardableResult
    public func decompress(chunks: AsyncThrowingStream<Data, Error>, to directory: AbsolutePath) async throws -> Int64 {
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else {
            throw AppleArchiverError.decompressionFailed("could not create a pipe")
        }
        let (readEnd, writeEnd) = (descriptors[0], descriptors[1])
        // An extraction that fails closes the read end; a write after that must fail with EPIPE rather than
        // raise SIGPIPE and end the process.
        _ = fcntl(writeEnd, F_SETNOSIGPIPE, 1)

        // Extraction blocks on the pipe, so it runs on its own thread rather than one of the cooperative pool's,
        // and the writes, which block while the pipe is full, run on a queue of their own.
        let extraction = Task<Void, Error> {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Thread {
                    defer { close(readEnd) }
                    do {
                        guard let readStream = ArchiveByteStream.fileStream(
                            fd: FileDescriptor(rawValue: readEnd),
                            automaticClose: false
                        ) else {
                            throw AppleArchiverError.decompressionFailed("could not read the pipe")
                        }
                        try Self.extract(readStream, to: directory)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }.start()
            }
        }
        let writer = DispatchQueue(label: "dev.tuist.apple-archiver.stream-writer")
        var bytes: Int64 = 0
        var chunksError: Error?
        var writeFailed = false
        do {
            for try await chunk in chunks {
                let written = await withCheckedContinuation { continuation in
                    writer.async { continuation.resume(returning: Self.write(chunk, to: writeEnd)) }
                }
                guard written else {
                    writeFailed = true
                    break
                }
                bytes += Int64(chunk.count)
            }
        } catch {
            chunksError = error
        }
        close(writeEnd)
        let extractionResult = await extraction.result
        if let chunksError { throw chunksError }
        try extractionResult.get()
        if writeFailed {
            throw AppleArchiverError.decompressionFailed("could not write to the pipe")
        }
        return bytes
    }

    private static func write(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    private static func extract(_ readStream: ArchiveByteStream, to directory: AbsolutePath) throws {
        let destination = FilePath(directory.pathString)
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
