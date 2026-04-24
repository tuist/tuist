import AppleArchive
import Foundation
import System

/// Decompresses an AppleArchive (.aar) file into `destinationDirectory`.
///
/// Exposed to the Erlang NIF layer via `@_cdecl("decompress_archive")`. The
/// Elixir side is responsible for sniffing the magic bytes and only routing
/// AppleArchive payloads here; ZIP payloads continue to use Erlang's `:zip`.
@_cdecl("decompress_archive")
public func decompressArchiveNIF(
    _ sourcePathPtr: UnsafePointer<CChar>,
    _ destinationDirPtr: UnsafePointer<CChar>,
    _ errorPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ errorLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let sourcePath = String(cString: sourcePathPtr)
    let destinationDir = String(cString: destinationDirPtr)

    do {
        try ArchiveDecompressor.decompress(
            archive: sourcePath,
            into: destinationDir
        )
        return 0
    } catch {
        writeCString(
            "{\"error\": \"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}",
            outputPtr: errorPtr,
            outputLen: errorLen
        )
        return 1
    }
}

enum ArchiveDecompressorError: LocalizedError {
    case openStreamFailed(String)
    case decompressionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openStreamFailed(detail): return "could not open archive stream: \(detail)"
        case let .decompressionFailed(detail): return "archive decompression failed: \(detail)"
        }
    }
}

enum ArchiveDecompressor {
    /// Extracts the entries of an AppleArchive file into `destination`.
    /// Mirrors `AppleArchiver.decompress` in the CLI so both ends agree on
    /// the stream pipeline (byte stream → decompression → decode → extract).
    static func decompress(archive archivePath: String, into destination: String) throws {
        let source = FilePath(archivePath)
        let target = FilePath(destination)

        guard let readStream = ArchiveByteStream.fileStream(
            path: source,
            mode: .readOnly,
            options: [],
            permissions: []
        ) else {
            throw ArchiveDecompressorError.openStreamFailed("file stream")
        }
        defer { try? readStream.close() }

        guard let decompressStream = ArchiveByteStream.decompressionStream(
            readingFrom: readStream
        ) else {
            throw ArchiveDecompressorError.openStreamFailed("decompression stream")
        }
        defer { try? decompressStream.close() }

        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream) else {
            throw ArchiveDecompressorError.openStreamFailed("decode stream")
        }
        defer { try? decodeStream.close() }

        guard let extractStream = ArchiveStream.extractStream(
            extractingTo: target,
            flags: [.ignoreOperationNotPermitted]
        ) else {
            throw ArchiveDecompressorError.openStreamFailed("extract stream")
        }
        defer { try? extractStream.close() }

        do {
            _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
        } catch {
            throw ArchiveDecompressorError.decompressionFailed(error.localizedDescription)
        }
    }
}

private func writeCString(
    _ string: String,
    outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    outputLen: UnsafeMutablePointer<Int32>
) {
    let data = Array(string.utf8)
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
    for (i, byte) in data.enumerated() {
        buffer[i] = CChar(bitPattern: byte)
    }
    outputPtr.pointee = buffer
    outputLen.pointee = Int32(data.count)
}
