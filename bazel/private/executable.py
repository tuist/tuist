"""Package native binaries without running them, using the Tuist CLI ZIP contract."""

import json
import shutil
import stat
import struct
import sys
import zipfile
from pathlib import Path, PurePosixPath


def target(header):
    architectures = {0x0100000C: "arm64", 0x01000007: "x86_64"}
    if header.startswith(b"#!"):
        if sys.platform not in ("darwin", "linux"):
            raise ValueError("Executable previews require macOS or Linux")
        return ("macos" if sys.platform == "darwin" else "linux"), []
    if header.startswith(b"\x7fELF\x02\x01") and len(header) >= 64:
        architecture = {62: "x86_64", 183: "arm64"}.get(
            int.from_bytes(header[18:20], "little")
        )
        if architecture:
            return "linux", [architecture]
    if len(header) >= 32 and struct.unpack_from("<I", header)[0] == 0xFEEDFACF:
        architecture = architectures.get(struct.unpack_from("<I", header, 4)[0])
        if architecture and struct.unpack_from("<I", header, 12)[0] == 2:
            return "macos", [architecture]
    if len(header) >= 8 and struct.unpack_from(">I", header)[0] == 0xCAFEBABE:
        count = struct.unpack_from(">I", header, 4)[0]
        if 0 < count <= 16 and 8 + count * 20 <= len(header):
            found = {
                architectures.get(struct.unpack_from(">I", header, 8 + index * 20)[0])
                for index in range(count)
            } - {None}
            if found:
                return "macos", sorted(found)
    raise ValueError(
        "Expected a macOS Mach-O, Linux ELF executable, or script with a shebang"
    )


def safe_path(name):
    path = PurePosixPath(name)
    if (
        not name
        or path.is_absolute()
        or ".." in path.parts
        or "\\" in name
        or "\0" in name
    ):
        raise ValueError("Unsafe executable distribution path")
    return path


def package(config, destination):
    entrypoint = config["executable"]
    safe_path(entrypoint)
    files = dict(config["files"])
    if entrypoint not in files:
        raise ValueError("Executable is missing from the distribution")
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(set(files) | set(config["empty_files"])):
            safe_path(name)
            if name == "tuist-preview.json":
                raise ValueError(
                    "tuist-preview.json is reserved for the preview entry point"
                )
            source = Path(files[name]) if name in files else None
            if source and (
                not source.is_file()
                or source.stat().st_mode & 0o111 == 0
                and name == entrypoint
            ):
                raise ValueError(
                    "Expected an executable file and regular runtime files"
                )
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (
                stat.S_IFREG
                | (0o755 if source and source.stat().st_mode & 0o111 else 0o644)
            ) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            with archive.open(entry, "w", force_zip64=True) as output:
                if source:
                    with source.open("rb") as stream:
                        shutil.copyfileobj(stream, output)
        manifest = zipfile.ZipInfo(
            "tuist-preview.json", date_time=(1980, 1, 1, 0, 0, 0)
        )
        manifest.create_system = 3
        manifest.external_attr = (stat.S_IFREG | 0o644) << 16
        archive.writestr(
            manifest, json.dumps({"executable": entrypoint}, separators=(",", ":"))
        )


def prepare(payload, directory, args):
    with zipfile.ZipFile(payload) as archive:
        manifest = archive.getinfo("tuist-preview.json")
        if manifest.file_size > 4096:
            raise ValueError("Invalid executable preview manifest")
        entrypoint = json.loads(archive.read(manifest))["executable"]
        safe_path(entrypoint)
        entry = archive.getinfo(entrypoint)
        if (
            not stat.S_ISREG(entry.external_attr >> 16)
            or entry.external_attr >> 16 & 0o111 == 0
        ):
            raise ValueError("The preview entry point must be executable")
        with archive.open(entry) as stream:
            platform, architectures = target(stream.read(4096))
    return (
        payload,
        "application/zip",
        "dev.tuist.executable.v1",
        {
            "schema": "tuist.executable.v1",
            "display_name": PurePosixPath(entrypoint).name,
            "executable": entrypoint,
            "platform": platform,
            "architectures": architectures,
        },
    )


if __name__ == "__main__":
    package(json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]))
