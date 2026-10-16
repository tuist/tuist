/// Prepares consumer-owned dSYM metadata rather than installing producer paths in LLDB's global source map.
enum CachedModuleSymbolsPreparationScript {
    static let value = #"""
    if plan is not None:
        import pathlib
        import plistlib
        import re
        import shutil
        import subprocess
        import tempfile

        relocations = {old: new for old, new in plan["mappings"] if old != new}
        products = sorted({os.path.realpath(environment[key]) for key in (
            "TARGET_BUILD_DIR", "BUILT_PRODUCTS_DIR", "CONFIGURATION_BUILD_DIR"
        ) if environment.get(key) and os.path.isdir(environment[key])})
        artifacts = [os.path.realpath(path) for path in plan["artifacts"]]
        target_mappings = sorted(mappings.items(), key=compiler_precedence)

        def target_namespace(path):
            # LLDB reverses target.source-map before matching breakpoints against module-remapped files.
            # Compose into that namespace, not directly into a physical path that would be remapped twice.
            for alias, current in target_mappings:
                root = current.rstrip("/")
                if path == root or path.startswith(root + "/"):
                    return alias.rstrip("/") + path[len(root):]
            return path

        native_products = set(plan["nativeProducts"])
        if environment.get("FULL_PRODUCT_NAME"):
            native_products.add(environment["FULL_PRODUCT_NAME"])
        symbol_products = set(native_products)
        for artifact in artifacts:
            info_path = pathlib.Path(artifact) / "Info.plist"
            if info_path.is_file():
                with info_path.open("rb") as info_file:
                    info = plistlib.load(info_file)
                symbol_products.update(pathlib.Path(library["LibraryPath"]).name for library in info["AvailableLibraries"])

        def inside(path, directory):
            return os.path.commonpath((os.path.realpath(path), directory)) == directory

        def consumer_owned(path):
            return any(inside(path, directory) for directory in products) and not any(
                inside(path, directory) for directory in artifacts
            )

        def dwarf_dump(path, sources=False):
            arguments = ["/usr/bin/xcrun", "dwarfdump", "--show-sources" if sources else "--uuid"]
            return subprocess.run(arguments + [str(path)], check=True, capture_output=True, text=True).stdout

        def uuids(output):
            return set(re.findall(r"UUID: ([A-Fa-f0-9-]+) ", output))

        if relocations and plan["requiresLinkedDebugInformation"]:
            # Static archives' object debug information must be linked against the consumer's addresses.
            # This creates a debug-only companion; the executable and cached archives stay unchanged.
            binaries = {}
            executable = environment.get("EXECUTABLE_PATH", "")
            if executable and environment.get("TARGET_BUILD_DIR"):
                binary = pathlib.Path(environment["TARGET_BUILD_DIR"]) / executable
                name = environment.get("FULL_PRODUCT_NAME", binary.name)
                binaries[binary] = pathlib.Path(environment["TARGET_BUILD_DIR"]) / (name + ".dSYM")
            for directory in products:
                for bundle in pathlib.Path(directory).iterdir():
                    if bundle.name not in native_products or bundle.suffix not in (".app", ".xctest", ".appex", ".framework") or not consumer_owned(bundle):
                        continue
                    for relative in ("Contents/Info.plist", "Info.plist", "Resources/Info.plist"):
                        info_path = bundle / relative
                        if not info_path.is_file():
                            continue
                        with info_path.open("rb") as info_file:
                            executable = plistlib.load(info_file).get("CFBundleExecutable", "")
                        if not executable or pathlib.Path(executable).name != executable:
                            break
                        for candidate in (bundle / "Contents/MacOS" / executable, bundle / executable):
                            if candidate.is_file():
                                binaries[candidate] = bundle.parent / (bundle.name + ".dSYM")
                                break
                        break
            cas_arguments = []
            config = pathlib.Path(environment.get("TARGET_TEMP_DIR", "")) / ".cas-config"
            if environment.get("COMPILATION_CACHE_ENABLE_CACHING") == "YES" and config.is_file():
                with config.open(encoding="utf-8") as config_file:
                    cas = json.load(config_file)
                cas_arguments += ["-cas", cas["CASPath"]]
                if cas.get("PluginPath"):
                    cas_arguments += ["-cas-plugin-path", cas["PluginPath"]]
                for options in cas.get("PluginOptions", []):
                    for key, value in options.items():
                        cas_arguments += ["-cas-plugin-option", key + "=" + value]
            for binary, dsym in sorted(binaries.items(), key=lambda entry: str(entry[0])):
                if not binary.is_file() or not consumer_owned(binary) or not consumer_owned(dsym):
                    continue
                binary_uuids = uuids(dwarf_dump(binary))
                if not binary_uuids or (dsym.is_dir() and uuids(dwarf_dump(dsym)) == binary_uuids):
                    continue
                with tempfile.TemporaryDirectory(prefix=".tuist-debug-symbols-", dir=dsym.parent) as temporary:
                    staged = pathlib.Path(temporary) / dsym.name
                    subprocess.run(["/usr/bin/xcrun", "dsymutil", *cas_arguments, str(binary), "-o", str(staged)], check=True)
                    if uuids(dwarf_dump(staged)) != binary_uuids or uuids(dwarf_dump(binary)) != binary_uuids:
                        raise ValueError("The debug companion no longer matches the consumer binary")
                    if dsym.exists():
                        shutil.rmtree(dsym)
                    os.rename(staged, dsym)

        if relocations:
            for directory in products:
                for dsym in sorted(pathlib.Path(directory).glob("*.dSYM")):
                    if dsym.name not in {name + ".dSYM" for name in symbol_products}:
                        continue
                    resources = dsym / "Contents/Resources"
                    if not resources.is_dir() or not consumer_owned(resources):
                        continue
                    output = dwarf_dump(dsym, sources=True)
                    observed = set(output.splitlines())
                    source_map = {old: target_namespace(new) for old, new in relocations.items() if old in observed}
                    if not source_map:
                        continue
                    for uuid in sorted(uuids(dwarf_dump(dsym))):
                        path = resources / (uuid + ".plist")
                        if path.is_symlink():
                            raise ValueError("Refusing to replace a symlinked dSYM source map")
                        info = {}
                        if path.exists():
                            with path.open("rb") as info_file:
                                info = plistlib.load(info_file)
                            if str(info.get("DBGVersion", "")) != "3":
                                print("Tuist: preserving custom dSYM source mappings in " + str(path), file=sys.stderr)
                                continue
                        previous = info.get("TuistSourcePathRemapping", {})
                        explicit = {old: new for old, new in info.get("DBGSourcePathRemapping", {}).items()
                                    if old not in previous or previous[old] != new}
                        info.update({"DBGVersion": "3", "DBGSourcePathRemapping": {**source_map, **explicit},
                                     "TuistSourcePathRemapping": {old: new for old, new in source_map.items() if old not in explicit}})
                        temporary = None
                        try:
                            with tempfile.NamedTemporaryFile(dir=resources, delete=False) as output_file:
                                temporary = output_file.name
                                plistlib.dump(info, output_file)
                            os.replace(temporary, path)
                        finally:
                            if temporary and os.path.exists(temporary):
                                os.unlink(temporary)
    """#
}
