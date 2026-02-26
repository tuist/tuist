import Foundation
#if canImport(MachO)
    import MachO
#else
    import MachOKitC
#endif

extension fat_header {
    mutating func swapIfNeeded(_ shouldSwap: Bool) {
        guard shouldSwap else { return }
        magic = magic.byteSwapped
        nfat_arch = nfat_arch.byteSwapped
    }
}

extension fat_arch {
    mutating func swapIfNeeded(_ shouldSwap: Bool) {
        guard shouldSwap else { return }
        cputype = cputype.byteSwapped
        cpusubtype = cpusubtype.byteSwapped
        offset = offset.byteSwapped
        size = size.byteSwapped
        align = align.byteSwapped
    }
}

extension mach_header {
    mutating func swapIfNeeded(_ shouldSwap: Bool) {
        guard shouldSwap else { return }
        magic = magic.byteSwapped
        cputype = cputype.byteSwapped
        cpusubtype = cpusubtype.byteSwapped
        filetype = filetype.byteSwapped
        ncmds = ncmds.byteSwapped
        sizeofcmds = sizeofcmds.byteSwapped
        flags = flags.byteSwapped
    }
}

extension mach_header_64 {
    mutating func swapIfNeeded(_ shouldSwap: Bool) {
        guard shouldSwap else { return }
        magic = magic.byteSwapped
        cputype = cputype.byteSwapped
        cpusubtype = cpusubtype.byteSwapped
        filetype = filetype.byteSwapped
        ncmds = ncmds.byteSwapped
        sizeofcmds = sizeofcmds.byteSwapped
        flags = flags.byteSwapped
        reserved = reserved.byteSwapped
    }
}

extension load_command {
    mutating func swapIfNeeded(_ shouldSwap: Bool) {
        guard shouldSwap else { return }
        cmd = cmd.byteSwapped
        cmdsize = cmdsize.byteSwapped
    }
}

extension uuid_command {
    mutating func swapIfNeeded(_ shouldSwap: Bool) {
        guard shouldSwap else { return }
        cmd = cmd.byteSwapped
        cmdsize = cmdsize.byteSwapped
        // The uuid field is 16 raw bytes; no integer fields to swap for endianness.
    }
}
