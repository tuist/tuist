import Foundation
#if canImport(MachO)
    import MachO
#else
    import MachOKitC
#endif
import Path
import XcodeGraph

// swiftlint:disable identifier_name
private let CPU_SUBTYPE_MASK = Int32(bitPattern: 0xFF00_0000)

// MARK: - Errors

enum PrecompiledMetadataProviderError: LocalizedError, Equatable {
    case architecturesNotFound(AbsolutePath)
    case metadataNotFound(AbsolutePath)

    // MARK: - FatalError

    var errorDescription: String? {
        switch self {
        case let .architecturesNotFound(path):
            return "Couldn't find architectures for binary at path \(path.pathString)"
        case let .metadataNotFound(path):
            return "Couldn't find metadata for binary at path \(path.pathString)"
        }
    }
}

// MARK: - Protocol

public protocol PrecompiledMetadataProviding {
    /// Returns the supported architectures of the binary at the given path.
    func architectures(binaryPath: AbsolutePath) throws -> [BinaryArchitecture]

    /// Returns how other binaries should link the binary at the given path (.dynamic or .static).
    func linking(binaryPath: AbsolutePath) throws -> BinaryLinking

    /// Uses 'dwarfdump' logic to find UUIDs for each arch (helps match .bcsymbolmap files).
    func uuids(binaryPath: AbsolutePath) throws -> Set<UUID>
}

// MARK: - PrecompiledMetadataProvider

/// Reads Mach-O metadata (arches, linking type, UUIDs) without calling deprecated swap_* APIs.
public class PrecompiledMetadataProvider: PrecompiledMetadataProviding {
    /// A local struct for arch/linking/UUID data
    typealias Metadata = (BinaryArchitecture, BinaryLinking, UUID?)

    public func architectures(binaryPath: AbsolutePath) throws -> [BinaryArchitecture] {
        let metadata = try readMetadatas(binaryPath: binaryPath)
        return metadata.map(\.0)
    }

    public func linking(binaryPath: AbsolutePath) throws -> BinaryLinking {
        let metadata = try readMetadatas(binaryPath: binaryPath)
        // If *any* arch is dynamic, the overall binary is dynamic.
        return metadata.contains(where: { $0.1 == .dynamic }) ? .dynamic : .static
    }

    public func uuids(binaryPath: AbsolutePath) throws -> Set<UUID> {
        let metadata = try readMetadatas(binaryPath: binaryPath)
        return Set(metadata.compactMap(\.2))
    }

    // MARK: - Internal

    private let sizeOfArchiveHeader: UInt64 = 60
    private let archiveHeaderSizeOffset: UInt64 = 56
    private let archiveFormatMagic = "!<arch>\n"
    private let archiveExtendedFormat = "#1/"

    /// Reads all arch/linking/UUID info for the given binary (whether fat or thin).
    func readMetadatas(binaryPath: AbsolutePath) throws -> [Metadata] {
        guard let binary = FileHandle(forReadingAtPath: binaryPath.pathString) else {
            throw PrecompiledMetadataProviderError.metadataNotFound(binaryPath)
        }
        defer { binary.closeFile() }

        // Peek at magic
        let magic: UInt32 = binary.read()
        // Reset to start
        binary.seek(to: 0)

        if isFat(magic) {
            return try readMetadatasFromFatHeader(binary: binary, magic: magic, binaryPath: binaryPath)
        } else if let singleMetadata = try readMetadataFromMachHeaderIfAvailable(binary: binary) {
            return [singleMetadata]
        } else {
            throw PrecompiledMetadataProviderError.metadataNotFound(binaryPath)
        }
    }

    private func readMetadatasFromFatHeader(
        binary: FileHandle,
        magic: UInt32,
        binaryPath: AbsolutePath
    ) throws -> [Metadata] {
        var header: fat_header = binary.read()
        header.swapIfNeeded(shouldSwap(magic))

        return try (0 ..< header.nfat_arch).map { _ in
            var fatArch: fat_arch = binary.read()
            fatArch.swapIfNeeded(shouldSwap(magic))

            let savedOffset = binary.currentOffset
            // Jump to that arch offset
            binary.seek(to: UInt64(fatArch.offset))

            // Attempt to parse Mach-O data
            let maybeMetadata = try readMetadataFromMachHeaderIfAvailable(binary: binary)
            // Restore offset
            binary.seek(to: savedOffset)

            if let metadata = maybeMetadata {
                return metadata
            } else {
                let maskedSubtype = fatArch.cpusubtype & ~CPU_SUBTYPE_MASK // 0x00000002

                // If we cannot parse Mach-O, fallback to static if cputype is known
                guard let arch = readBinaryArchitecture(
                    cputype: fatArch.cputype,
                    cpusubtype: maskedSubtype
                ) else {
                    throw PrecompiledMetadataProviderError.architecturesNotFound(binaryPath)
                }
                return (arch, .static, nil)
            }
        }
    }

    private func readMetadataFromMachHeaderIfAvailable(binary: FileHandle) throws -> Metadata? {
        readArchiveFormatIfAvailable(binary)

        let currentOffset = binary.currentOffset
        let magic: UInt32 = binary.read()
        binary.seek(to: currentOffset)

        guard isMagic(magic) else {
            return nil
        }

        let (cputype, cpusubtype, filetype, ncmds) = try readMachHeader(binary: binary, magic: magic)
        guard let arch = readBinaryArchitecture(cputype: cputype, cpusubtype: cpusubtype) else {
            return nil
        }

        var foundUUID: UUID?
        for _ in 0 ..< ncmds {
            let cmdStart = binary.currentOffset
            var loadCmd: load_command = binary.read()
            loadCmd.swapIfNeeded(shouldSwap(magic))

            guard loadCmd.cmd == LC_UUID else {
                binary.seek(to: cmdStart + UInt64(loadCmd.cmdsize))
                continue
            }

            // re-read the entire uuid_command
            binary.seek(to: cmdStart)
            var uuidCmd: uuid_command = binary.read()
            uuidCmd.swapIfNeeded(shouldSwap(magic))

            foundUUID = UUID(uuid: uuidCmd.uuid)
            break
        }

        let linking: BinaryLinking = (filetype == MH_DYLIB) ? .dynamic : .static
        return (arch, linking, foundUUID)
    }

    private func readMachHeader(
        binary: FileHandle,
        magic: UInt32
    ) throws -> (cpu_type_t, cpu_subtype_t, UInt32, UInt32) {
        if is64(magic) {
            var header64: mach_header_64 = binary.read()
            header64.swapIfNeeded(shouldSwap(magic))
            return (header64.cputype, header64.cpusubtype, header64.filetype, header64.ncmds)
        } else {
            var header32: mach_header = binary.read()
            header32.swapIfNeeded(shouldSwap(magic))
            return (header32.cputype, header32.cpusubtype, header32.filetype, header32.ncmds)
        }
    }

    private func readArchiveFormatIfAvailable(_ binary: FileHandle) {
        let currentOffset = binary.currentOffset
        let data = binary.readData(ofLength: 8)
        binary.seek(to: currentOffset)

        guard let magicStr = String(data: data, encoding: .ascii),
              magicStr == archiveFormatMagic
        else { return }

        binary.seek(to: currentOffset + archiveHeaderSizeOffset)
        guard let sizeString = binary.readString(ofLength: 10) else { return }

        let size = strtoul(sizeString, nil, 10)
        // skip the archive header
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

    // MARK: - Architecture Mapping

    private func readBinaryArchitecture(cputype: cpu_type_t, cpusubtype: cpu_subtype_t) -> BinaryArchitecture? {
        BinaryArchitecture(cputype: cputype, subtype: cpusubtype)
    }

    // MARK: - Helpers

    private func isMagic(_ magic: UInt32) -> Bool {
        [MH_MAGIC, MH_MAGIC_64, MH_CIGAM, MH_CIGAM_64, FAT_MAGIC, FAT_CIGAM].contains(magic)
    }

    private func isFat(_ magic: UInt32) -> Bool {
        [FAT_MAGIC, FAT_CIGAM].contains(magic)
    }

    private func is64(_ magic: UInt32) -> Bool {
        [MH_MAGIC_64, MH_CIGAM_64].contains(magic)
    }

    /// If magic is CIGAM or FAT_CIGAM, it's big-endian -> we need to byte-swap
    private func shouldSwap(_ magic: UInt32) -> Bool {
        [MH_CIGAM, MH_CIGAM_64, FAT_CIGAM].contains(magic)
    }
}

// swiftlint:enable identifier_name
