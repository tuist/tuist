import Foundation
import MachO
import TSCBasic
import TuistGraph
import TuistSupport

enum PrecompiledMetadataProviderError: FatalError, Equatable {
    case architecturesNotFound(AbsolutePath)
    case metadataNotFound(AbsolutePath)

    // MARK: - FatalError

    var description: String {
        switch self {
        case let .architecturesNotFound(path):
            return "Couldn't find architectures for binary at path \(path.pathString)"
        case let .metadataNotFound(path):
            return "Couldn't find metadata for binary at path \(path.pathString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .architecturesNotFound:
            return .abort
        case .metadataNotFound:
            return .abort
        }
    }
}

public protocol PrecompiledMetadataProviding {
    /// It returns the supported architectures of the binary at the given path.
    /// - Parameter binaryPath: Binary path.
    func architectures(binaryPath: AbsolutePath) throws -> [BinaryArchitecture]

    /// Return how other binaries should link the binary at the given path.
    /// - Parameter binaryPath: Path to the binary.
    func linking(binaryPath: AbsolutePath) throws -> BinaryLinking

    /// It uses 'dwarfdump' to dump the UUIDs of each architecture.
    /// The UUIDs allows us to know which .bcsymbolmap files belong to this binary.
    /// - Parameter binaryPath: Path to the binary.
    func uuids(binaryPath: AbsolutePath) throws -> Set<UUID>
}

/// PrecompiledMetadataProvider reads a framework/library metadata using the Mach-o file format.
/// Useful documentation:
/// - https://opensource.apple.com/source/cctools/cctools-809/misc/lipo.c
/// - https://opensource.apple.com/source/xnu/xnu-4903.221.2/EXTERNAL_HEADERS/mach-o/loader.h.auto.html

public class PrecompiledMetadataProvider: PrecompiledMetadataProviding {
    public func architectures(binaryPath: AbsolutePath) throws -> [BinaryArchitecture] {
        let metadata = try readMetadatas(binaryPath: binaryPath)
        return metadata.map(\.0)
    }

    public func linking(binaryPath: AbsolutePath) throws -> BinaryLinking {
        let metadata = try readMetadatas(binaryPath: binaryPath)
        return metadata.contains { $0.1 == BinaryLinking.dynamic } ? .dynamic : .static
    }

    public func uuids(binaryPath: AbsolutePath) throws -> Set<UUID> {
        let metadata = try readMetadatas(binaryPath: binaryPath)
        return Set(metadata.compactMap(\.2))
    }

    typealias Metadata = (BinaryArchitecture, BinaryLinking, UUID?)

    private let sizeOfArchiveHeader: UInt64 = 60
    private let archiveHeaderSizeOffset: UInt64 = 56
    private let archiveFormatMagic = "!<arch>\n"
    private let archiveExtendedFormat = "#1/"

    func readMetadatas(binaryPath: AbsolutePath) throws -> [Metadata] {
        guard let binary = FileHandle(forReadingAtPath: binaryPath.pathString) else {
            throw PrecompiledMetadataProviderError.metadataNotFound(binaryPath)
        }

        defer {
            binary.closeFile()
        }

        let magic: UInt32 = binary.read()
        binary.seek(to: 0)

        if isFat(magic) {
            return try readMetadatasFromFatHeader(binary: binary, binaryPath: binaryPath)
        } else if let metadata = try readMetadataFromMachHeaderIfAvailable(binary: binary) {
            return [metadata]
        } else {
            throw PrecompiledMetadataProviderError.metadataNotFound(binaryPath)
        }
    }

    private func readMetadatasFromFatHeader(
        binary: FileHandle,
        binaryPath: AbsolutePath
        // swiftlint:disable:next large_tuple
    ) throws -> [(BinaryArchitecture, BinaryLinking, UUID?)] {
        let currentOffset = binary.currentOffset
        let magic: UInt32 = binary.read()
        binary.seek(to: currentOffset)

        var header: fat_header = binary.read()
        if shouldSwap(magic) {
            swap_fat_header(&header, NX_UnknownByteOrder)
        }

        return try (0 ..< header.nfat_arch).map { _ in
            var fatArch: fat_arch = binary.read()
            if shouldSwap(magic) {
                swap_fat_arch(&fatArch, 1, NX_UnknownByteOrder)
            }
            let currentOffset = binary.currentOffset

            binary.seek(to: UInt64(fatArch.offset))
            if let value = try readMetadataFromMachHeaderIfAvailable(binary: binary) {
                binary.seek(to: currentOffset)
                return value
            } else {
                binary.seek(to: currentOffset)

                guard let architecture = readBinaryArchitecture(cputype: fatArch.cputype, cpusubtype: fatArch.cpusubtype) else {
                    throw PrecompiledMetadataProviderError.architecturesNotFound(binaryPath)
                }

                return (architecture, .static, nil)
            }
        }
    }

    // swiftlint:disable:next function_body_length large_tuple
    private func readMetadataFromMachHeaderIfAvailable(binary: FileHandle) throws -> (BinaryArchitecture, BinaryLinking, UUID?)? {
        readArchiveFormatIfAvailable(binary: binary)

        let currentOffset = binary.currentOffset
        let magic: UInt32 = binary.read()
        binary.seek(to: currentOffset)

        guard isMagic(magic) else { return nil }

        let cputype: cpu_type_t
        let cpusubtype: cpu_subtype_t
        let filetype: UInt32
        let numOfCommands: UInt32

        if is64(magic) {
            var header: mach_header_64 = binary.read()
            if shouldSwap(magic) {
                swap_mach_header_64(&header, NX_UnknownByteOrder)
            }

            cputype = header.cputype
            cpusubtype = header.cpusubtype
            filetype = header.filetype
            numOfCommands = header.ncmds
        } else {
            var header: mach_header = binary.read()
            if shouldSwap(magic) {
                swap_mach_header(&header, NX_UnknownByteOrder)
            }
            cputype = header.cputype
            cpusubtype = header.cpusubtype
            filetype = header.filetype
            numOfCommands = header.ncmds
        }

        guard let binaryArchitecture = readBinaryArchitecture(cputype: cputype, cpusubtype: cpusubtype)
        else { return nil }

        var uuid: UUID?

        for _ in 0 ..< numOfCommands {
            let currentOffset = binary.currentOffset
            var loadCommand: load_command = binary.read()

            if shouldSwap(magic) {
                swap_load_command(&loadCommand, NX_UnknownByteOrder)
            }

            guard loadCommand.cmd == LC_UUID else {
                binary.seek(to: currentOffset + UInt64(loadCommand.cmdsize))
                continue
            }

            binary.seek(to: currentOffset)

            var uuidCommand: uuid_command = binary.read()

            if shouldSwap(magic) {
                swap_uuid_command(&uuidCommand, NX_UnknownByteOrder)
            }

            uuid = UUID(uuid: uuidCommand.uuid)
            break
        }

        let binaryLinking = filetype == MH_DYLIB ? BinaryLinking.dynamic : BinaryLinking.static
        return (binaryArchitecture, binaryLinking, uuid)
    }

    private func readBinaryArchitecture(cputype: cpu_type_t, cpusubtype: cpu_subtype_t) -> BinaryArchitecture? {
        guard let archInfo = NXGetArchInfoFromCpuType(cputype, cpusubtype),
              let arch = BinaryArchitecture(rawValue: String(cString: archInfo.pointee.name))
        else {
            return nil
        }
        return arch
    }

    private func readArchiveFormatIfAvailable(binary: FileHandle) {
        let currentOffset = binary.currentOffset
        let magic = binary.readData(ofLength: 8)
        binary.seek(to: currentOffset)

        guard String(data: magic, encoding: .ascii) == archiveFormatMagic else { return }

        binary.seek(to: archiveHeaderSizeOffset)
        guard let sizeString = binary.readString(ofLength: 10) else { return }

        let size = strtoul(sizeString, nil, 10)
        binary.seek(to: 8 + sizeOfArchiveHeader + UInt64(size))

        guard let name = binary.readString(ofLength: 16) else { return }
        binary.seek(to: binary.currentOffset - 16)

        if name.hasPrefix(archiveExtendedFormat) {
            let nameSize = strtoul(String(name.dropFirst(3)), nil, 10)
            binary.seek(to: binary.currentOffset + sizeOfArchiveHeader + UInt64(nameSize))
        } else {
            binary.seek(to: binary.currentOffset + sizeOfArchiveHeader)
        }
    }

    private func isMagic(_ magic: UInt32) -> Bool {
        [MH_MAGIC, MH_MAGIC_64, MH_CIGAM, MH_CIGAM_64, FAT_MAGIC, FAT_CIGAM].contains(magic)
    }

    private func is64(_ magic: UInt32) -> Bool {
        [MH_MAGIC_64, MH_CIGAM_64].contains(magic)
    }

    private func shouldSwap(_ magic: UInt32) -> Bool {
        [MH_CIGAM, MH_CIGAM_64, FAT_CIGAM].contains(magic)
    }

    private func isFat(_ magic: UInt32) -> Bool {
        [FAT_MAGIC, FAT_CIGAM].contains(magic)
    }
}

extension FileHandle {
    fileprivate var currentOffset: UInt64 { offsetInFile }

    fileprivate func seek(to offset: UInt64) {
        seek(toFileOffset: offset)
    }

    fileprivate func read<T>() -> T {
        readData(ofLength: MemoryLayout<T>.size).withUnsafeBytes { $0.load(as: T.self) }
    }

    fileprivate func readString(ofLength length: Int) -> String? {
        let sizeData = readData(ofLength: length)
        return String(data: sizeData, encoding: .ascii)
    }
}
