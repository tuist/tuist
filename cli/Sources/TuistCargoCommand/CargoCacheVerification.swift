import Foundation
import Path
import TuistREAPI

/// An opt-in canary for cache hits, like kache's `KACHE_VERIFY_INPUT_PREDICTIONS` and `KACHE_VERIFY`. Off unless set:
///
/// - `TUIST_CARGO_VERIFY=sampled|always` checks the inputs a hit was keyed by. A strict compilation keyed by a remembered
///   source list runs rustc for dep-info only and compares the sources it names; the hit is served when they agree. A
///   recorded compilation or build-script run keyed by a remembered read set runs recorded and compares what it read.
/// - `TUIST_CARGO_VERIFY_RECOMPILE=sampled|always` compiles hits and compares their outputs with the stored entry,
///   classified as a match, a difference in a Mach-O image's link-edit data only, or a content difference.
///
/// A sampled hit whose check needs a compilation (or disagreed before one) compiles in place, exactly as an uncached
/// build would, instead of restoring: the build uses fresh outputs whatever the check finds. Verification never stores
/// or replaces the checked unit's entry. Its dependents key its fresh outputs, though, so when those differ from the
/// stored ones by a byte, the dependents miss and are stored as in an uncached build. Findings are logged under
/// `TUIST_DEBUG`; checked compilations count as `verifications` (compiled rather than reused), and checks that found an
/// unkeyed read, a content difference or a failure the hit would have hidden count as `divergences`.
enum CargoCacheVerification {
    static let inputsVariable = "TUIST_CARGO_VERIFY"
    static let recompileVariable = "TUIST_CARGO_VERIFY_RECOMPILE"
    /// One unit in this many is checked under `sampled`.
    static let rate: UInt64 = 64

    enum Mode { case off, sampled, always }

    static func mode(_ value: String?) -> Mode {
        switch value?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "sampled": .sampled
        case "always", "1", "true": .always
        default: .off
        }
    }

    /// Whether `mode` checks the unit named `identity`. Decided by the identity's digest, not by a counter: every
    /// compilation is a new request, and drawing the sample from what names the unit checks the same units on every
    /// build and in every checkout, so a finding reproduces.
    static func selects(_ mode: Mode, identity: String) -> Bool {
        switch mode {
        case .off: false
        case .always: true
        case .sampled: UInt64(REAPI.digest(Data(identity.utf8)).hash.prefix(16), radix: 16).map { $0 % rate == 0 } ?? false
        }
    }

    /// Which checks select a unit: its inputs, its outputs, both or neither.
    struct Selection {
        let inputs: Bool
        let outputs: Bool
        var any: Bool { inputs || outputs }
    }

    static func selection(identity: @autoclosure () -> String, environment: [String: String]) -> Selection {
        let inputs = mode(environment[inputsVariable]), outputs = mode(environment[recompileVariable])
        guard inputs != .off || outputs != .off else { return Selection(inputs: false, outputs: false) }
        let identity = identity()
        return Selection(inputs: selects(inputs, identity: identity), outputs: selects(outputs, identity: identity))
    }

    /// A compilation as every checkout of the project names it: crate name and types, whether it is a test harness,
    /// Cargo's package, its `--cfg`s and its root source relative to the package. Not the cache key, which changes with
    /// every edit, nor `-C metadata`, which folds the path of a path dependency outside the workspace.
    static func identity(_ arguments: [String], environment: [String: String], directory: AbsolutePath) -> String {
        let base = URL(fileURLWithPath: directory.pathString, isDirectory: true)
        let roots = [environment["CARGO_MANIFEST_DIR"], directory.pathString].compactMap { $0 }
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let source = arguments.dropFirst().first { $0.hasSuffix(".rs") }.map { source -> String in
            let path = URL(fileURLWithPath: source, relativeTo: base).standardizedFileURL.path
            return roots.first { path.hasPrefix($0 + "/") }.map { String(path.dropFirst($0.count + 1)) } ?? source
        }
        return [
            "rustc",
            CargoCacheInputs.values("--crate-name", in: arguments).joined(separator: ","),
            CargoCacheInputs.values("--crate-type", in: arguments).joined(separator: ","),
            arguments.contains("--test") ? "test" : "",
            environment["CARGO_PKG_NAME"] ?? "", environment["CARGO_PKG_VERSION"] ?? "",
            CargoCacheInputs.values("--cfg", in: arguments).joined(separator: "\u{1f}"),
            source ?? "",
        ].joined(separator: "\u{0}")
    }

    /// A build-script run as every checkout names it.
    static func scriptIdentity(environment: [String: String]) -> String {
        ["run", environment["CARGO_PKG_NAME"] ?? "", environment["CARGO_PKG_VERSION"] ?? "", environment["TARGET"] ?? ""]
            .joined(separator: "\u{0}")
    }

    // MARK: - Findings

    struct Finding {
        enum Outcome: String {
            case match = "ok"
            /// The key named inputs the fresh run did not read: it misses more often than needed, never wrongly.
            case narrower
            /// A Mach-O image differs only in its link-edit data (symbol table, debug map, signature) and the load
            /// commands describing it.
            case pathDebug = "path-debug"
            case content
            /// The fresh run read an input the key did not name: an edit to it would have been served a stale hit.
            case unkeyed
            /// The check could not run; nothing was learned.
            case failed
        }

        /// `sources`, `reads` or `outputs`.
        let check: String
        let outcome: Outcome
        var detail = ""

        var divergent: Bool { outcome == .content || outcome == .unkeyed }
    }

    /// A sampled hit that compiles instead of restoring, and what its compilation is compared with.
    struct Plan {
        /// The stored entry the hit would have restored.
        let entry: REAPI.ActionResult
        /// The remembered sources a strict compilation was keyed by.
        let sources: [URL]?
        /// The recorded read set a recorded compilation was keyed by.
        let reads: CargoReadSet?
        let selection: Selection
        /// Found before compiling, such as a dep-info run that disagreed with the remembered sources.
        var findings: [Finding] = []
    }

    /// The checks `selection` can make of `invocation`, or `nil` when none applies (such as an inputs check of a unit
    /// keyed without a remembered source list or read set), so the hit restores without looking its entry up again.
    static func checks(_ selection: Selection, invocation: any CargoCacheAction) -> Selection? {
        let inputs = selection.inputs
            && (rememberedSources(invocation) != nil || (invocation as? CargoRecordedInvocation)?.reads != nil)
        guard inputs || selection.outputs else { return nil }
        return Selection(inputs: inputs, outputs: selection.outputs)
    }

    private static func rememberedSources(_ invocation: any CargoCacheAction) -> [URL]? {
        guard let strict = invocation as? CargoCacheInvocation, strict.sourceIndex != nil, !strict.isDeferred else { return nil }
        return strict.compilerInputs?.sources
    }

    /// What to do with a selected hit: `nil` restores it as usual, a plan compiles it and compares. `entry` is the
    /// stored entry, read without restoring it; without one the compilation is an ordinary miss.
    static func plan(
        invocation: any CargoCacheAction, checks: Selection, entry: REAPI.ActionResult?, process: CargoProcess
    ) async -> Plan? {
        guard let entry else { return nil }
        let sources = rememberedSources(invocation)
        let reads = (invocation as? CargoRecordedInvocation)?.reads
        // A remembered source list is checked without compiling: rustc names every source it reads in dep-info.
        if let strict = invocation as? CargoCacheInvocation, let sources, checks.inputs, !checks.outputs {
            let finding = await checkSources(strict, sources: sources, process: process)
            guard finding.divergent else {
                report([finding], name: strict.name, environment: strict.environment)
                return nil
            }
            return Plan(entry: entry, sources: sources, reads: nil, selection: checks, findings: [finding])
        }
        return Plan(entry: entry, sources: sources, reads: reads, selection: checks)
    }

    /// The compilation's arguments, without the compiler, for a run that writes only dep-info to `depInfo`: every
    /// `--emit` and the incremental session are dropped, so it writes nothing else and touches no session.
    static func dependencyInfoArguments(_ arguments: [String], depInfo: String, remap: [String]) -> [String] {
        var result: [String] = []
        var index = 1
        let original = CargoCacheInputs.withoutIncremental(arguments)
        while index < original.count {
            if original[index] == "--emit" { index += 2; continue }
            if !original[index].hasPrefix("--emit=") { result.append(original[index]) }
            index += 1
        }
        return result + ["--emit=dep-info=\(depInfo)"] + remap
    }

    /// Runs rustc for dep-info only, as the compilation itself would run, and compares the sources it names with the
    /// remembered list the key was computed from.
    static func checkSources(_ invocation: CargoCacheInvocation, sources: [URL], process: CargoProcess) async -> Finding {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tuist-cargo-verify-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let depInfo = directory.appendingPathComponent("inputs.d")
        let arguments = dependencyInfoArguments(
            invocation.arguments, depInfo: depInfo.path, remap: invocation.remapArguments
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try await process.capture(
                invocation.arguments[0], arguments: arguments, environment: invocation.environment,
                directory: invocation.directory
            )
            let text = try String(contentsOf: depInfo, encoding: .utf8)
            let base = URL(fileURLWithPath: invocation.directory.pathString, isDirectory: true)
            let fresh = try CargoCacheInvocation.dependencies(text).map {
                URL(fileURLWithPath: $0, relativeTo: base).standardizedFileURL
            }
            let unkeyedVariables = text.split(separator: "\n").filter { $0.hasPrefix("# env-dep:") }
                .map { String($0.dropFirst(10).prefix { $0 != "=" }) }.filter(CargoCacheInvocation.isIgnored)
            var finding = compareSources(
                invocation, sources: sources, fresh: (fresh, CargoCacheInvocation.readVariables(text))
            )
            if !unkeyedVariables.isEmpty {
                finding = Finding(
                    check: "sources", outcome: .unkeyed,
                    detail: "reads unkeyed variables \(unkeyedVariables.sorted().joined(separator: ", "))"
                        + (finding.detail.isEmpty ? "" : "; " + finding.detail)
                )
            }
            return finding
        } catch {
            return Finding(check: "sources", outcome: .failed, detail: "the dep-info run failed (\(error))")
        }
    }

    /// Compares the sources and package variables (`CargoCacheInvocation.isKeyedWhenRead`) a strict compilation's
    /// remembered list named with those a fresh dep-info names.
    static func compareSources(
        _ invocation: CargoCacheInvocation, sources: [URL], fresh: (sources: [URL], variables: [String])
    ) -> Finding {
        func inputs(_ sources: [URL], _ variables: [String]) -> Set<String> {
            Set(sources.map { invocation.relocation.relative($0.path) } + variables.map { "env " + $0 })
        }
        return compare(
            used: inputs(sources, invocation.compilerInputs?.variables ?? []), fresh: inputs(fresh.sources, fresh.variables),
            check: "sources"
        )
    }

    static func compare(used: CargoReadSet, fresh: CargoReadSet) -> Finding {
        compare(
            used: Set(used.entries.map { "\($0.kind) \($0.name)" }), fresh: Set(fresh.entries.map { "\($0.kind) \($0.name)" }),
            check: "reads"
        )
    }

    private static func compare(used: Set<String>, fresh: Set<String>, check: String) -> Finding {
        func list(_ names: Set<String>) -> String {
            let sorted = names.sorted()
            return sorted.prefix(8).joined(separator: ", ") + (sorted.count > 8 ? " and \(sorted.count - 8) more" : "")
        }
        let unkeyed = fresh.subtracting(used), unread = used.subtracting(fresh)
        if !unkeyed.isEmpty {
            return Finding(
                check: check, outcome: .unkeyed,
                detail: "read \(list(unkeyed)), which the key did not name"
                    + (unread.isEmpty ? "" : "; did not read \(list(unread))")
            )
        }
        if !unread.isEmpty { return Finding(check: check, outcome: .narrower, detail: "did not read \(list(unread))") }
        return Finding(check: check, outcome: .match)
    }

    // MARK: - Outputs

    /// One output compared with its stored counterpart.
    typealias Artifact = (name: String, outcome: Finding.Outcome, detail: String)

    /// Compares the outputs a compilation just wrote with the stored entry's, one file at a time.
    ///
    /// Incremental codegen is not reproducible: rustc names codegen units after its session, so two incremental
    /// compilations of the same sources write differently named objects, and rlibs and linked images that hold or
    /// name them. When either side compiled incrementally (the fresh compilation was, or the two name different
    /// objects), only metadata and dep-info are compared. Metadata covers every source change through the crate hash;
    /// differences codegen alone would show go unseen there.
    static func compareOutputs(
        _ entry: REAPI.ActionResult, invocation: any CargoCacheAction, root: URL, remote: (any REAPICacheStoring)?
    ) async -> Finding {
        let produced = Set((try? invocation.outputFiles()) ?? [])
        let stored = Set(entry.outputFiles.map(\.path))
        let metadataOnly = CargoCacheInputs.withoutIncremental(invocation.arguments) != invocation.arguments
            || stored.filter(isCodegenObject) != produced.filter(isCodegenObject)
        // A recorded binary's `.dSYM` is written by `dsymutil` when it is published, which a verified compilation never is.
        let bundle = (invocation as? CargoRecordedInvocation)?.debugBundle
        let compares = { (name: String) in
            (bundle.map { name != $0 && !name.hasPrefix($0 + "/") } ?? true)
                && (!metadataOnly || name.hasSuffix(".rmeta") || name.hasSuffix(".d"))
        }
        let files = entry.outputFiles.filter { compares($0.path) }.sorted { $0.path < $1.path }
        let compared = await withStored(files.map(\.digest), root: root, remote: remote) { stored -> [Artifact]? in
            var artifacts: [Artifact] = []
            for file in files {
                guard let cached = stored(file.digest) else { return nil }
                guard var fresh = try? Data(contentsOf: invocation.output.appendingPathComponent(file.path)) else {
                    artifacts.append((file.path, .content, "not produced by the compilation"))
                    continue
                }
                if file.path.hasSuffix(".d") {
                    guard let relocated = invocation.storedOutput(fresh) else {
                        artifacts.append((file.path, .content, "names a path outside the known roots"))
                        continue
                    }
                    fresh = relocated
                }
                let (outcome, detail) = classify(cached: cached, fresh: fresh)
                artifacts.append((file.path, outcome, detail))
            }
            return artifacts
        }
        guard let readable = compared, var artifacts = readable else {
            return Finding(check: "outputs", outcome: .failed, detail: "the stored outputs cannot be read")
        }
        for name in produced.subtracting(stored).filter(compares).sorted() {
            artifacts.append((name, .content, "not in the stored entry"))
        }
        let finding = summarize(artifacts)
        guard metadataOnly else { return finding }
        let note = "incremental codegen is not reproducible, so only metadata and dep-info were compared"
        return Finding(
            check: finding.check, outcome: finding.outcome, detail: finding.detail.isEmpty ? note : finding.detail + "; " + note
        )
    }

    /// A codegen unit's object, which rustc leaves beside an rlib or image when debug information is split.
    static func isCodegenObject(_ name: String) -> Bool {
        name.hasSuffix(".rcgu.o") || name.hasSuffix(".rcgu.dwo")
    }

    /// One finding for a set of artifacts: the worst outcome, naming each artifact that differs.
    static func summarize(_ artifacts: [Artifact]) -> Finding {
        let content = artifacts.filter { $0.outcome == .content }, paths = artifacts.filter { $0.outcome == .pathDebug }
        func named(_ items: [Artifact]) -> String {
            let shown = items.prefix(4).map { $0.detail.isEmpty ? $0.name : "\($0.name) (\($0.detail))" }
            return shown.joined(separator: ", ") + (items.count > 4 ? " and \(items.count - 4) more" : "")
        }
        var parts: [String] = []
        if !content.isEmpty { parts.append("content: " + named(content)) }
        if !paths.isEmpty { parts.append("path-debug: " + named(paths)) }
        let outcome: Finding.Outcome = content.isEmpty ? (paths.isEmpty ? .match : .pathDebug) : .content
        return Finding(check: "outputs", outcome: outcome, detail: parts.joined(separator: "; "))
    }

    /// Runs `body` with a reader of stored blobs, which returns a blob's contents when they match its digest. Blobs the
    /// store lacks are downloaded from `remote` into a staging directory first, never into the store, and each is read
    /// only when asked for, so an entry of many large files is never held in memory whole. `nil` when a missing blob
    /// cannot be downloaded.
    static func withStored<T>(
        _ digests: [REAPI.Digest], root: URL, remote: (any REAPICacheStoring)?,
        body: (_ read: (REAPI.Digest) -> Data?) async -> T
    ) async -> T? {
        let store = CargoBlobStore(root: root)
        let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        var missing: [REAPI.Digest: URL] = [:]
        for digest in digests where !store.contains(digest) {
            missing[digest] = staging.appendingPathComponent(digest.hash)
        }
        if !missing.isEmpty {
            guard let remote, (try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)) != nil,
                  let download = try? await remote.downloadBlobs(missing),
                  download.available.isSuperset(of: Set(missing.keys)) else { return nil }
        }
        let staged = missing
        return await body { digest in
            guard let data = try? Data(contentsOf: staged[digest] ?? store.path(digest)), REAPI.digest(data) == digest
            else { return nil }
            return data
        }
    }

    /// Classifies a stored artifact against a fresh one, like kache's `verify_compare` but without its tolerance for
    /// differences inside any path-like bytes, which also hid changed values such as dates, git refs and URLs. Here a
    /// correct hit differs from a fresh compilation in no path: an output naming a machine root is stored only under a
    /// key that binds the root (`CargoRelocation.boundRoots`), so it is restored only where that root is the same. Only
    /// a Mach-O image's link-edit data is exempt, as `boundRoots` exempts it: its debug map names object files by
    /// absolute path, and its UUID and signature cover the map.
    static func classify(cached: Data, fresh: Data) -> (Finding.Outcome, String) {
        if cached == fresh { return (.match, "") }
        let left = [UInt8](cached), right = [UInt8](fresh)
        if let left = withoutLinkEdit(left), let right = withoutLinkEdit(right), left == right {
            return (.pathDebug, "link-edit data only")
        }
        let shorter = min(left.count, right.count)
        let offset = (0 ..< shorter).first { left[$0] != right[$0] } ?? shorter
        func excerpt(_ bytes: [UInt8]) -> String {
            bytes[min(offset, bytes.count) ..< min(offset + 16, bytes.count)].map { byte in
                (0x20 ..< 0x7F).contains(byte) && byte != 0x5C ? String(UnicodeScalar(byte)) : String(format: "\\x%02x", byte)
            }.joined()
        }
        return (
            .content,
            "first difference at byte \(offset) of \(left.count)/\(right.count): stored \"\(excerpt(left))\" fresh \"\(excerpt(right))\""
        )
    }

    /// A 64-bit Mach-O image up to its link-edit segment, with the load commands that describe link-edit data (and its
    /// UUID, a digest that covers it) cleared: a linked binary's debug map names object files by absolute path, so an
    /// image linked in another directory differs there and nowhere else. `nil` for anything else.
    static func withoutLinkEdit(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count > 32, bytes[0 ..< 4] == [0xCF, 0xFA, 0xED, 0xFE] else { return nil }
        func integer<T: FixedWidthInteger>(_ offset: Int, _: T.Type) -> T? {
            guard offset >= 0, offset + MemoryLayout<T>.size <= bytes.count else { return nil }
            return bytes[offset ..< offset + MemoryLayout<T>.size].enumerated()
                .reduce(T(0)) { $0 | T($1.element) << (8 * $1.offset) }
        }
        // LC_SYMTAB, LC_DYSYMTAB, LC_ID_DYLIB, LC_UUID, LC_CODE_SIGNATURE, LC_FUNCTION_STARTS, LC_DATA_IN_CODE,
        // LC_DYLD_INFO(_ONLY), LC_DYLD_EXPORTS_TRIE and LC_DYLD_CHAINED_FIXUPS.
        let cleared: Set<UInt32> = [0x2, 0xB, 0xD, 0x1B, 0x1D, 0x26, 0x29, 0x22, 0x8000_0022, 0x8000_0033, 0x8000_0034]
        guard let count = integer(16, UInt32.self) else { return nil }
        var result = bytes
        var linkEdit: Int?
        var offset = 32
        for _ in 0 ..< min(count, 4096) {
            guard let command = integer(offset, UInt32.self), let size = integer(offset + 4, UInt32.self), size >= 8,
                  offset + Int(size) <= bytes.count else { return nil }
            let isLinkEdit = command == 0x19 && offset + 48 <= bytes.count
                && bytes[offset + 8 ..< offset + 24].prefix(while: { $0 != 0 }).elementsEqual("__LINKEDIT".utf8)
            if isLinkEdit, let fileOffset = integer(offset + 40, UInt64.self), fileOffset <= UInt64(bytes.count) {
                linkEdit = Int(fileOffset)
            }
            if isLinkEdit || cleared.contains(command) {
                for index in offset + 8 ..< offset + Int(size) {
                    result[index] = 0
                }
            }
            offset += Int(size)
        }
        guard let linkEdit else { return nil }
        return Array(result.prefix(linkEdit))
    }

    // MARK: - Reporting

    static func report(_ findings: [Finding], name: String, environment: [String: String]) {
        guard environment["TUIST_DEBUG"] == "1" else { return }
        // Every build script compiles as `build_script_build`; its package tells them apart.
        let name = name.hasPrefix("build_script_") ? "\(environment["CARGO_PKG_NAME"] ?? "") \(name)" : name
        let lines = findings.map { finding in
            "Tuist Cargo cache: verified \(name) \(finding.check): \(finding.outcome.rawValue)"
                + (finding.detail.isEmpty ? "" : " (\(finding.detail))") + "\n"
        }
        FileHandle.standardError.write(Data(lines.joined().utf8))
    }
}
