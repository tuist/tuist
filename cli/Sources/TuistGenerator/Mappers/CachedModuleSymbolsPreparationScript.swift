/// Prepares consumer-owned dSYM metadata rather than installing producer paths in LLDB's global source map.
enum CachedModuleSymbolsPreparationScript {
    static let value = #"""
    if plan is not None:
        import concurrent.futures
        import fcntl
        import hashlib
        import pathlib
        import plistlib
        import re
        import shutil
        import subprocess
        import tempfile

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

        # Paths built in place, or prefix-mapped ones that target.source-map resolves, need no plist or companion.
        # Compare spellings, not real paths: LLDB matches breakpoints by spelling and does not resolve symlinks.
        relocations = {old: new for old, new in plan["mappings"] if old != new and target_namespace(new) != old}

        native_products = set(plan["nativeProducts"])
        if environment.get("FULL_PRODUCT_NAME"):
            native_products.add(environment["FULL_PRODUCT_NAME"])
        symbol_products = set(native_products)
        for artifact in artifacts:
            info_path = pathlib.Path(artifact) / "Info.plist"
            if info_path.is_file():
                with info_path.open("rb") as info_file:
                    info = plistlib.load(info_file)
                symbol_products.update(pathlib.Path(library["LibraryPath"]).name for library in info.get("AvailableLibraries", []))

        def consumer_owned(path):
            path = os.path.realpath(path)
            return any(os.path.commonpath((path, directory)) == directory for directory in products) and not any(
                os.path.commonpath((path, directory)) == directory for directory in artifacts
            )

        def find_tool(name):
            # In Xcode's environment, an xcrun call costs more than the symbol query it runs, so resolve each tool once.
            return subprocess.run(["/usr/bin/xcrun", "--find", name], check=True, capture_output=True, text=True).stdout.strip()

        dwarfdump = find_tool("dwarfdump") if relocations else None

        def dwarf_dump(path, sources=False):
            arguments = [dwarfdump, "--show-sources" if sources else "--uuid"]
            return subprocess.run(arguments + [str(path)], check=True, capture_output=True, text=True).stdout

        def uuids(output):
            return set(re.findall(r"UUID: ([A-Fa-f0-9-]+) ", output))

        def parallel(function, items):
            # The symbol tools run as subprocesses, so threads overlap their work. Results keep the items' order.
            with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
                return list(pool.map(function, items))

        failed_companions = set()
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
            dsymutil = find_tool("dsymutil") if binaries else None
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
            def prepare_companion(binary, dsym):
                if not binary.is_file() or not consumer_owned(binary) or not consumer_owned(dsym):
                    return
                lock_path = dsym.parent / ("." + dsym.name + ".tuist.lock")
                with os.fdopen(os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), "r+") as lock:
                    fcntl.flock(lock, fcntl.LOCK_EX)
                    binary_uuids = uuids(dwarf_dump(binary))
                    if not binary_uuids or (dsym.is_dir() and uuids(dwarf_dump(dsym)) == binary_uuids):
                        return
                    if dsym.is_symlink():
                        raise ValueError("Refusing to replace a symlinked debug companion")
                    marker = "Contents/Resources/tuist-debug-companion.json"
                    if dsym.exists():
                        owner = dsym / marker
                        if not consumer_owned(owner) or owner.is_symlink() or not owner.is_file():
                            raise ValueError("Preserving an existing debug companion not owned by Tuist; rebuild its symbols")
                        with owner.open(encoding="utf-8") as owner_file:
                            ownership = json.load(owner_file)
                        if ownership != {"version": 1, "uuids": sorted(uuids(dwarf_dump(dsym)))}:
                            raise ValueError("The existing debug companion no longer matches Tuist's ownership record")
                        for custom in (dsym / "Contents/Resources").glob("*.plist"):
                            if custom.is_symlink():
                                raise ValueError("Preserving a custom debug companion source map")
                            with custom.open("rb") as custom_file:
                                custom_info = plistlib.load(custom_file)
                            if (str(custom_info.get("DBGVersion")) != "3" or
                                custom_info.get("DBGSourcePathRemapping", {}) != custom_info.get("TuistSourcePathRemapping", {}) or
                                set(custom_info) - {"DBGVersion", "DBGSourcePathRemapping", "TuistSourcePathRemapping"}):
                                raise ValueError("Preserving a custom debug companion source map")
                    with tempfile.TemporaryDirectory(prefix=".tuist-debug-symbols-", dir=dsym.parent) as temporary:
                        staged = pathlib.Path(temporary) / dsym.name
                        subprocess.run([dsymutil, *cas_arguments, str(binary), "-o", str(staged)], check=True)
                        if uuids(dwarf_dump(staged)) != binary_uuids or uuids(dwarf_dump(binary)) != binary_uuids:
                            raise ValueError("The debug companion no longer matches the consumer binary")
                        with (staged / marker).open("w", encoding="utf-8") as owner_file:
                            json.dump({"version": 1, "uuids": sorted(binary_uuids)}, owner_file)
                        if dsym.exists():
                            shutil.rmtree(dsym)
                        os.rename(staged, dsym)

            def prepare(entry):
                binary, dsym = entry
                try:
                    prepare_companion(binary, dsym)
                except Exception as error:
                    return os.path.realpath(dsym), "Tuist: debug companion could not be prepared for " + str(binary) + ": " + str(error)

            for failure in parallel(prepare, sorted(binaries.items(), key=lambda entry: str(entry[0]))):
                if failure:
                    failed_companions.add(failure[0])
                    print(failure[1], file=sys.stderr)

        if relocations:
            relocations_digest = hashlib.sha256(json.dumps(sorted(relocations)).encode("utf-8")).hexdigest()

            def dsym_symbols(dsym):
                # Listing sources reads every line table, so reuse the result until the dSYM's DWARF files or the
                # relocated paths change. The record lives next to the companion lock, so dSYMs only gain UUID plists.
                record_path = dsym.parent / ("." + dsym.name + ".tuist-sources.json")
                dwarf = dsym / "Contents/Resources/DWARF"
                key = [relocations_digest, sorted(
                    [entry.name, status.st_dev, status.st_ino, status.st_size, status.st_mtime_ns]
                    for entry in (dwarf.iterdir() if dwarf.is_dir() else [])
                    for status in [entry.stat()]
                )]
                if record_path.is_file() and not record_path.is_symlink():
                    try:
                        with record_path.open(encoding="utf-8") as record_file:
                            record = json.load(record_file)
                        if record["key"] == key:
                            return set(record["uuids"]), set(record["observed"])
                    except Exception:
                        pass
                observed = set(dwarf_dump(dsym, sources=True).splitlines()) & relocations.keys()
                dsym_uuids = uuids(dwarf_dump(dsym))
                temporary = None
                try:
                    with tempfile.NamedTemporaryFile(
                        "w", encoding="utf-8", prefix=".tuist-sources-", dir=dsym.parent, delete=False
                    ) as record_file:
                        temporary = record_file.name
                        json.dump({"key": key, "uuids": sorted(dsym_uuids), "observed": sorted(observed)}, record_file)
                    os.replace(temporary, record_path)
                except OSError:
                    pass
                finally:
                    if temporary and os.path.exists(temporary):
                        os.unlink(temporary)
                return dsym_uuids, observed

            def update_source_maps(dsym):
                messages = []
                resources = dsym / "Contents/Resources"
                dsym_uuids, observed = dsym_symbols(dsym)
                source_map = {old: target_namespace(new) for old, new in relocations.items() if old in observed}
                for uuid in sorted(dsym_uuids):
                    path = resources / (uuid + ".plist")
                    if path.is_symlink():
                        messages.append("Tuist: preserving symlinked dSYM source map " + str(path))
                        continue
                    info = {}
                    if path.exists():
                        try:
                            with path.open("rb") as info_file:
                                info = plistlib.load(info_file)
                            if not isinstance(info, dict):
                                raise ValueError("Expected a dSYM source-map dictionary")
                        except Exception as error:
                            messages.append("Tuist: preserving unreadable dSYM source map " + str(path) + ": " + str(error))
                            continue
                        if str(info.get("DBGVersion", "")) != "3":
                            messages.append("Tuist: preserving custom dSYM source mappings in " + str(path))
                            continue
                    if not source_map and not info.get("TuistSourcePathRemapping"):
                        continue
                    previous = info.get("TuistSourcePathRemapping", {})
                    explicit = {old: new for old, new in info.get("DBGSourcePathRemapping", {}).items()
                                if old not in previous or previous[old] != new}
                    updated = {**info, "DBGVersion": "3", "DBGSourcePathRemapping": {**source_map, **explicit},
                               "TuistSourcePathRemapping": {old: new for old, new in source_map.items() if old not in explicit}}
                    if updated == info:
                        continue
                    temporary = None
                    try:
                        with tempfile.NamedTemporaryFile(dir=resources, delete=False) as output_file:
                            temporary = output_file.name
                            plistlib.dump(updated, output_file)
                        os.replace(temporary, path)
                    finally:
                        if temporary and os.path.exists(temporary):
                            os.unlink(temporary)
                return messages

            symbol_bundles = {name + ".dSYM" for name in symbol_products}
            dsyms = [
                dsym for directory in products for dsym in sorted(pathlib.Path(directory).glob("*.dSYM"))
                if dsym.name in symbol_bundles and os.path.realpath(dsym) not in failed_companions
                and (dsym / "Contents/Resources").is_dir() and consumer_owned(dsym / "Contents/Resources")
            ]
            for messages in parallel(update_source_maps, dsyms):
                for message in messages:
                    print(message, file=sys.stderr)
        if failed_companions:
            raise ValueError("Some cached debug companions could not be prepared; unrelated module mappings were retained")
    """#
}
