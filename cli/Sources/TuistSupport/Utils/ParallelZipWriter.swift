import FileSystem
import Foundation
import Path
import ZIPFoundation

enum ParallelZipWriterError: LocalizedError, Equatable {
    case zip64Required
    case unreadableItem(String)

    var errorDescription: String? {
        switch self {
        case .zip64Required:
            return "The archive exceeds the limits of the ZIP format without ZIP64 extensions."
        case let .unreadableItem(path):
            return "The item at \(path) could not be read while archiving."
        }
    }
}

private struct PlannedEntry: Sendable {
    enum Kind: Sendable {
        case file
        case directory
        case symlink
    }

    let path: AbsolutePath
    let name: String
    let kind: Kind
    let permissions: UInt16
    let modificationDate: Date
    let uncompressedSize: Int64
}

private struct CompressedPayload: Sendable {
    let compressionMethod: UInt16
    let checksum: UInt32
    let compressedSize: Int64
    let uncompressedSize: Int64
    let inlineData: Data?
    let blobPath: AbsolutePath?

    static func empty(method: UInt16 = 0) -> CompressedPayload {
        CompressedPayload(
            compressionMethod: method,
            checksum: 0,
            compressedSize: 0,
            uncompressedSize: 0,
            inlineData: Data(),
            blobPath: nil
        )
    }
}

private enum ZipContainer {
    static let localHeaderSignature: UInt32 = 0x0403_4B50
    static let centralDirectorySignature: UInt32 = 0x0201_4B50
    static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    static let versionNeededToExtract: UInt16 = 20
    static let versionMadeBy: UInt16 = 789
    static let utf8NameFlag: UInt16 = 1 << 11
    static let localHeaderByteCount = 30

    static func localHeader(for entry: PlannedEntry, payload: CompressedPayload) -> Data {
        let name = Data(entry.name.utf8)
        let (time, date) = dosTimestamp(from: entry.modificationDate)
        var header = Data()
        header.appendLittleEndian(localHeaderSignature)
        header.appendLittleEndian(versionNeededToExtract)
        header.appendLittleEndian(utf8NameFlag)
        header.appendLittleEndian(payload.compressionMethod)
        header.appendLittleEndian(time)
        header.appendLittleEndian(date)
        header.appendLittleEndian(payload.checksum)
        header.appendLittleEndian(UInt32(payload.compressedSize))
        header.appendLittleEndian(UInt32(payload.uncompressedSize))
        header.appendLittleEndian(UInt16(name.count))
        header.appendLittleEndian(UInt16(0))
        header.append(name)
        return header
    }

    static func centralDirectoryHeader(
        for entry: PlannedEntry,
        payload: CompressedPayload,
        localHeaderOffset: Int64
    ) -> Data {
        let name = Data(entry.name.utf8)
        let (time, date) = dosTimestamp(from: entry.modificationDate)
        var header = Data()
        header.appendLittleEndian(centralDirectorySignature)
        header.appendLittleEndian(versionMadeBy)
        header.appendLittleEndian(versionNeededToExtract)
        header.appendLittleEndian(utf8NameFlag)
        header.appendLittleEndian(payload.compressionMethod)
        header.appendLittleEndian(time)
        header.appendLittleEndian(date)
        header.appendLittleEndian(payload.checksum)
        header.appendLittleEndian(UInt32(payload.compressedSize))
        header.appendLittleEndian(UInt32(payload.uncompressedSize))
        header.appendLittleEndian(UInt16(name.count))
        header.appendLittleEndian(UInt16(0))
        header.appendLittleEndian(UInt16(0))
        header.appendLittleEndian(UInt16(0))
        header.appendLittleEndian(UInt16(0))
        header.appendLittleEndian(externalAttributes(for: entry))
        header.appendLittleEndian(UInt32(localHeaderOffset))
        header.append(name)
        return header
    }

    static func endOfCentralDirectory(entryCount: Int, byteCount: Int, offset: Int64) -> Data {
        var end = Data()
        end.appendLittleEndian(endOfCentralDirectorySignature)
        end.appendLittleEndian(UInt16(0))
        end.appendLittleEndian(UInt16(0))
        end.appendLittleEndian(UInt16(entryCount))
        end.appendLittleEndian(UInt16(entryCount))
        end.appendLittleEndian(UInt32(byteCount))
        end.appendLittleEndian(UInt32(offset))
        end.appendLittleEndian(UInt16(0))
        return end
    }

    static func externalAttributes(for entry: PlannedEntry) -> UInt32 {
        let type: UInt16
        switch entry.kind {
        case .file: type = UInt16(S_IFREG)
        case .directory: type = UInt16(S_IFDIR)
        case .symlink: type = UInt16(S_IFLNK)
        }
        return UInt32(type | entry.permissions) << 16
    }

    static func dosTimestamp(from date: Date) -> (time: UInt16, date: UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = components.year ?? 1980
        guard year >= 1980, year <= 2107 else { return (0, 33) }
        let time = UInt16((components.hour ?? 0) << 11 | (components.minute ?? 0) << 5 | ((components.second ?? 0) / 2))
        let dosDate = UInt16((year - 1980) << 9 | (components.month ?? 1) << 5 | (components.day ?? 1))
        return (time, dosDate)
    }
}

/// Writes a ZIP archive whose entries are deflated concurrently.
///
/// The format compresses entries independently, so the encoder does not have to
/// be the serial bottleneck it is when entries are written one at a time. The
/// container itself is assembled sequentially in enumeration order.
struct ParallelZipWriter {
    private static let inlineCompressionLimit: Int64 = 1024 * 1024
    private static let bufferSize = 256 * 1024

    private let concurrency: Int
    private let fileSystem: FileSysteming

    init(
        concurrency: Int = ProcessInfo.processInfo.activeProcessorCount,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.concurrency = max(1, concurrency)
        self.fileSystem = fileSystem
    }

    func write(contentsOf source: AbsolutePath, to destination: AbsolutePath) async throws {
        let entries = try plannedEntries(in: source)
        guard entries.count <= Int(UInt16.max) else { throw ParallelZipWriterError.zip64Required }

        let scratch = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-parallel-zip")
        do {
            let payloads = try await compress(entries, into: scratch)
            try requireNonZip64(entries: entries, payloads: payloads)
            try assemble(entries: entries, payloads: payloads, at: destination)
        } catch {
            try? await fileSystem.remove(scratch)
            throw error
        }
        try await fileSystem.remove(scratch)
    }

    // MARK: - Planning

    private func plannedEntries(in source: AbsolutePath) throws -> [PlannedEntry] {
        let fileManager = FileManager()
        return try fileManager.subpathsOfDirectory(atPath: source.pathString).sorted().map { subpath in
            let path = source.appending(try RelativePath(validating: subpath))
            let attributes = try fileManager.attributesOfItem(atPath: path.pathString)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
            let kind: PlannedEntry.Kind
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory: kind = .directory
            case .typeSymbolicLink: kind = .symlink
            default: kind = .file
            }
            return PlannedEntry(
                path: path,
                name: kind == .directory ? "\(subpath)/" : subpath,
                kind: kind,
                permissions: permissions,
                modificationDate: attributes[.modificationDate] as? Date ?? Date(),
                uncompressedSize: kind == .file ? ((attributes[.size] as? NSNumber)?.int64Value ?? 0) : 0
            )
        }
    }

    // MARK: - Compression

    private func compress(_ entries: [PlannedEntry], into scratch: AbsolutePath) async throws -> [CompressedPayload] {
        var payloads = [CompressedPayload?](repeating: nil, count: entries.count)

        try await withThrowingTaskGroup(of: (Int, CompressedPayload).self) { group in
            var next = 0
            for _ in 0 ..< min(concurrency, entries.count) {
                let index = next
                group.addTask { (index, try Self.payload(for: entries[index], index: index, scratch: scratch)) }
                next += 1
            }
            while let (index, payload) = try await group.next() {
                payloads[index] = payload
                if next < entries.count {
                    let index = next
                    group.addTask { (index, try Self.payload(for: entries[index], index: index, scratch: scratch)) }
                    next += 1
                }
            }
        }

        return payloads.compactMap { $0 }
    }

    private static func payload(for entry: PlannedEntry, index: Int, scratch: AbsolutePath) throws -> CompressedPayload {
        switch entry.kind {
        case .directory:
            return .empty()
        case .symlink:
            let target = try FileManager().destinationOfSymbolicLink(atPath: entry.path.pathString)
            let data = Data(target.utf8)
            return CompressedPayload(
                compressionMethod: 0,
                checksum: data.crc32(checksum: 0),
                compressedSize: Int64(data.count),
                uncompressedSize: Int64(data.count),
                inlineData: data,
                blobPath: nil
            )
        case .file:
            guard entry.uncompressedSize > 0 else { return .empty() }
            return try deflate(entry, index: index, scratch: scratch)
        }
    }

    private static func deflate(_ entry: PlannedEntry, index: Int, scratch: AbsolutePath) throws -> CompressedPayload {
        guard let input = FileHandle(forReadingAtPath: entry.path.pathString) else {
            throw ParallelZipWriterError.unreadableItem(entry.path.pathString)
        }
        defer { try? input.close() }
        let provider: Provider = { _, size in try input.read(upToCount: size) ?? Data() }

        if entry.uncompressedSize <= inlineCompressionLimit {
            var output = Data()
            let checksum = try Data.compress(
                size: entry.uncompressedSize,
                bufferSize: bufferSize,
                provider: provider,
                consumer: { output.append($0) }
            )
            return CompressedPayload(
                compressionMethod: 8,
                checksum: checksum,
                compressedSize: Int64(output.count),
                uncompressedSize: entry.uncompressedSize,
                inlineData: output,
                blobPath: nil
            )
        }

        let blobPath = scratch.appending(component: "\(index).deflate")
        FileManager.default.createFile(atPath: blobPath.pathString, contents: nil)
        guard let output = FileHandle(forWritingAtPath: blobPath.pathString) else {
            throw ParallelZipWriterError.unreadableItem(blobPath.pathString)
        }
        defer { try? output.close() }
        var written: Int64 = 0
        let checksum = try Data.compress(
            size: entry.uncompressedSize,
            bufferSize: bufferSize,
            provider: provider,
            consumer: { chunk in
                try output.write(contentsOf: chunk)
                written += Int64(chunk.count)
            }
        )
        try output.close()

        return CompressedPayload(
            compressionMethod: 8,
            checksum: checksum,
            compressedSize: written,
            uncompressedSize: entry.uncompressedSize,
            inlineData: nil,
            blobPath: blobPath
        )
    }

    // MARK: - Assembly

    private func assemble(
        entries: [PlannedEntry],
        payloads: [CompressedPayload],
        at destination: AbsolutePath
    ) throws {
        FileManager.default.createFile(atPath: destination.pathString, contents: nil)
        guard let output = FileHandle(forWritingAtPath: destination.pathString) else {
            throw ParallelZipWriterError.unreadableItem(destination.pathString)
        }
        defer { try? output.close() }

        var centralDirectory = Data()
        var offset: Int64 = 0

        for (entry, payload) in zip(entries, payloads) {
            let header = ZipContainer.localHeader(for: entry, payload: payload)
            try output.write(contentsOf: header)
            centralDirectory.append(
                ZipContainer.centralDirectoryHeader(for: entry, payload: payload, localHeaderOffset: offset)
            )
            try writeBody(of: payload, to: output)
            offset += Int64(header.count) + payload.compressedSize
        }

        try output.write(contentsOf: centralDirectory)
        try output.write(
            contentsOf: ZipContainer.endOfCentralDirectory(
                entryCount: entries.count,
                byteCount: centralDirectory.count,
                offset: offset
            )
        )
    }

    private func writeBody(of payload: CompressedPayload, to output: FileHandle) throws {
        if let inlineData = payload.inlineData {
            guard !inlineData.isEmpty else { return }
            try output.write(contentsOf: inlineData)
        } else if let blobPath = payload.blobPath {
            guard let input = FileHandle(forReadingAtPath: blobPath.pathString) else {
                throw ParallelZipWriterError.unreadableItem(blobPath.pathString)
            }
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: Self.bufferSize), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
        }
    }

    private func requireNonZip64(entries: [PlannedEntry], payloads: [CompressedPayload]) throws {
        let limit = Int64(UInt32.max)
        var total: Int64 = 0
        for (entry, payload) in zip(entries, payloads) {
            guard payload.compressedSize <= limit, payload.uncompressedSize <= limit else {
                throw ParallelZipWriterError.zip64Required
            }
            total += Int64(ZipContainer.localHeaderByteCount + entry.name.utf8.count) + payload.compressedSize
            guard total <= limit else { throw ParallelZipWriterError.zip64Required }
        }
    }
}

extension Data {
    fileprivate mutating func appendLittleEndian(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    fileprivate mutating func appendLittleEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }
}
