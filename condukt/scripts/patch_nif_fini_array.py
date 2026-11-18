#!/usr/bin/env python3
"""Zero DT_FINI_ARRAYSZ in an ELF64 cdylib's .dynamic section.

The microsandbox NIF statically links aws-lc-sys (transitively via rustls).
AWS-LC registers two `__attribute__((destructor))` functions that walk a
linked list of per-thread RNG state at process exit and call cleanup
function pointers from each entry's vtable.

On BEAM Linux, `exit()` does not join the scheduler threads first, so by
the time `_dl_fini` runs those destructors the per-thread state has been
partially freed and a vtable's function pointer is stale. The indirect
call jumps to load_base + 0 (the ELF header bytes) and the process
segfaults with exit code 139 just after the test suite has reported
`0 failures`. The bashkit NIF documents the same hazard.

This script patches the built .so to set `DT_FINI_ARRAYSZ = 0`, so
`_dl_fini` iterates zero times for our object. The CRT
`__do_global_dtors_aux` entry is also skipped, which is fine: it would
have called `__cxa_finalize(&__dso_handle)` to run C++/atexit handlers
none of which need to run when the host process is exiting anyway.

Usage:
    patch_nif_fini_array.py <path-to-cdylib.so>
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

ELF_MAGIC = b"\x7fELF"
EI_CLASS_64 = 2
EI_DATA_LE = 1
PT_DYNAMIC = 2
DT_FINI_ARRAYSZ = 0x1C


def patch(path: Path) -> bool:
    data = bytearray(path.read_bytes())
    if data[:4] != ELF_MAGIC:
        raise SystemExit(f"{path}: not an ELF file")
    if data[4] != EI_CLASS_64:
        raise SystemExit(f"{path}: only ELF64 is supported")
    endian = "<" if data[5] == EI_DATA_LE else ">"

    # Elf64_Ehdr layout: e_phoff @0x20 (Q), e_phentsize @0x36 (H), e_phnum @0x38 (H)
    (e_phoff,) = struct.unpack_from(endian + "Q", data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from(endian + "HH", data, 0x36)

    # Elf64_Phdr layout for 64-bit:
    # p_type(I) p_flags(I) p_offset(Q) p_vaddr(Q) p_paddr(Q) p_filesz(Q) p_memsz(Q) p_align(Q)
    dyn_offset = None
    dyn_filesz = None
    for i in range(e_phnum):
        base = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(endian + "I", data, base)[0]
        if p_type == PT_DYNAMIC:
            dyn_offset = struct.unpack_from(endian + "Q", data, base + 0x08)[0]
            dyn_filesz = struct.unpack_from(endian + "Q", data, base + 0x20)[0]
            break
    if dyn_offset is None:
        raise SystemExit(f"{path}: no PT_DYNAMIC segment found")

    # Walk .dynamic entries: each is { d_tag(Sxword), d_un(Xword) }, 16 bytes
    patched = False
    for off in range(dyn_offset, dyn_offset + dyn_filesz, 16):
        d_tag = struct.unpack_from(endian + "q", data, off)[0]
        if d_tag == 0:  # DT_NULL terminates the array
            break
        if d_tag == DT_FINI_ARRAYSZ:
            current = struct.unpack_from(endian + "Q", data, off + 8)[0]
            if current == 0:
                print(f"{path}: DT_FINI_ARRAYSZ already 0, nothing to patch")
                return False
            struct.pack_into(endian + "Q", data, off + 8, 0)
            print(f"{path}: zeroed DT_FINI_ARRAYSZ (was {current} bytes)")
            patched = True
            break
    if not patched:
        print(f"{path}: no DT_FINI_ARRAYSZ entry found, nothing to patch")
        return False

    path.write_bytes(bytes(data))
    return True


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    for arg in sys.argv[1:]:
        patch(Path(arg))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
