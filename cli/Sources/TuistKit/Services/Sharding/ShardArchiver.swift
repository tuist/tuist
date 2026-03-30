#if os(macOS)
    import AppleArchive
    import Foundation
    import Path
    import System

    enum ShardArchiverError: LocalizedError, Equatable {
        case compressionFailed(String)
        case decompressionFailed(String)

        var errorDescription: String? {
            switch self {
            case let .compressionFailed(detail):
                return "Failed to compress shard bundle: \(detail)"
            case let .decompressionFailed(detail):
                return "Failed to decompress shard bundle: \(detail)"
            }
        }
    }

    enum ShardArchiver {
        static func compress(directory: AbsolutePath, to archivePath: AbsolutePath) throws {
            let source = FilePath(directory.pathString)
            let destination = FilePath(archivePath.pathString)

            guard let writeStream = ArchiveByteStream.fileStream(
                path: destination,
                mode: .writeOnly,
                options: [.create, .truncate],
                permissions: [.ownerReadWrite, .groupRead, .otherRead]
            ) else {
                throw ShardArchiverError.compressionFailed("could not create file stream")
            }
            defer { try? writeStream.close() }

            guard let compressStream = ArchiveByteStream.compressionStream(
                using: .lzfse,
                writingTo: writeStream
            ) else {
                throw ShardArchiverError.compressionFailed("could not create compression stream")
            }
            defer { try? compressStream.close() }

            guard let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream) else {
                throw ShardArchiverError.compressionFailed("could not create encode stream")
            }
            defer { try? encodeStream.close() }

            let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,UID,GID,MOD,FLG,MTM,CTM,SLC,LNK")!
            try encodeStream.writeDirectoryContents(archiveFrom: source, keySet: keySet)

            try encodeStream.close()
            try compressStream.close()
            try writeStream.close()
        }

        static func decompress(archive: AbsolutePath, to directory: AbsolutePath) throws {
            let source = FilePath(archive.pathString)
            let destination = FilePath(directory.pathString)

            guard let readStream = ArchiveByteStream.fileStream(
                path: source,
                mode: .readOnly,
                options: [],
                permissions: []
            ) else {
                throw ShardArchiverError.decompressionFailed("could not open archive")
            }
            defer { try? readStream.close() }

            guard let decompressStream = ArchiveByteStream.decompressionStream(
                readingFrom: readStream
            ) else {
                throw ShardArchiverError.decompressionFailed("could not create decompression stream")
            }
            defer { try? decompressStream.close() }

            guard let decodeStream = ArchiveStream.decodeStream(
                readingFrom: decompressStream
            ) else {
                throw ShardArchiverError.decompressionFailed("could not create decode stream")
            }
            defer { try? decodeStream.close() }

            guard let extractStream = ArchiveStream.extractStream(
                extractingTo: destination,
                flags: [.ignoreOperationNotPermitted]
            ) else {
                throw ShardArchiverError.decompressionFailed("could not create extract stream")
            }
            defer { try? extractStream.close() }

            _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)

            try extractStream.close()
            try decodeStream.close()
            try decompressStream.close()
            try readStream.close()
        }
    }
#endif
