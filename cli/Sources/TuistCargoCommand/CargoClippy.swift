import Foundation
import Path
import TuistREAPI

/// A compilation `cargo clippy` runs through the toolchain's `clippy-driver`, which Cargo starts as its workspace wrapper
/// (`RUSTC_WORKSPACE_WRAPPER`): the hook sees `clippy-driver rustc <arguments>`. The driver is rustc with lints, so its
/// compilations are keyed like rustc's, plus what changes what a successful run prints beyond its arguments: the
/// driver's version, the lint arguments `cargo clippy` passes in `CLIPPY_ARGS`, `CLIPPY_DISABLE_DOCS_LINKS`, the
/// package's `Cargo.toml` and the `.clippy.toml` or `clippy.toml` Clippy would load. Lints read manifests: the one in
/// the driver's working directory (the workspace root) and the configuration file also appear in dep-info, the
/// package's own does not. Other workspace wrappers stay uncached.
struct CargoClippy {
    /// What `clippy-driver --version` printed.
    let version: String
    let driver: URL

    /// Variables the driver reads, keyed for its compilations only: Cargo sets them for the whole command, and rustc
    /// compilations of dependencies in the same command never read them.
    static let environment: Set = ["CLIPPY_ARGS", "CLIPPY_CONF_DIR", "CLIPPY_DISABLE_DOCS_LINKS"]

    /// Whether Cargo's workspace wrapper leaves compilations cacheable: none, or `clippy-driver`.
    static func admitsWorkspaceWrapper(_ environment: [String: String]) -> Bool {
        guard let wrapper = environment["RUSTC_WORKSPACE_WRAPPER"], !wrapper.isEmpty else { return true }
        return URL(fileURLWithPath: wrapper).lastPathComponent == "clippy-driver"
    }

    /// The rustc arguments of `clippy-driver rustc <arguments>` started as Cargo's workspace wrapper, `nil` otherwise.
    static func compilerArguments(_ arguments: [String], environment: [String: String]) -> [String]? {
        guard arguments.count > 1, URL(fileURLWithPath: arguments[0]).lastPathComponent == "clippy-driver",
              let wrapper = environment["RUSTC_WORKSPACE_WRAPPER"], wrapper == arguments[0],
              URL(fileURLWithPath: arguments[1]).lastPathComponent == "rustc"
        else { return nil }
        return Array(arguments.dropFirst())
    }

    /// The driver of a `clippy-driver rustc` invocation, provided it is the one of the toolchain `sysroot`, so it runs
    /// with the compiler libraries the key already holds.
    static func prepare(
        _ arguments: [String], sysroot: URL, environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> CargoClippy? {
        let base = URL(fileURLWithPath: directory.pathString, isDirectory: true)
        let driver = URL(fileURLWithPath: arguments[0], relativeTo: base).standardizedFileURL.resolvingSymlinksInPath()
        guard driver == sysroot.appendingPathComponent("bin/clippy-driver").resolvingSymlinksInPath(),
              FileManager.default.isExecutableFile(atPath: driver.path),
              // The driver passes `--sysroot $SYSROOT` to rustc when the arguments name none, a standard library the
              // key would not hold.
              environment["SYSROOT"] == nil,
              // `cargo clippy` joins its lint arguments with this separator, which reads as part of a word.
              !refusesLints(([arguments.joined(separator: " ")] + (environment["CLIPPY_ARGS"] ?? "")
                      .components(separatedBy: "__CLIPPY_HACKERY__")).joined(separator: " "))
        else { return nil }
        // Once per session, like the toolchain identity: the driver's content is keyed as well.
        let memo = environment["TUIST_CARGO_SESSION"].map {
            URL(fileURLWithPath: $0).appendingPathComponent("clippy-" + REAPI.digest(Data(driver.path.utf8)).hash)
        }
        if let memo, let version = try? String(contentsOf: memo, encoding: .utf8), !version.isEmpty {
            return CargoClippy(version: version, driver: driver)
        }
        let output = try await process.capture(
            driver.path, arguments: ["--version"], environment: environment, directory: directory
        )
        let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("clippy ") else { return nil }
        if let memo { try? version.write(to: memo, atomically: true, encoding: .utf8) }
        return CargoClippy(version: version, driver: driver)
    }

    /// The key inputs the driver adds to rustc's, read again on every fingerprint.
    func keyInputs(environment: [String: String], directory: AbsolutePath, hasher: CargoInputHasher) throws -> [String] {
        var inputs = ["clippy", version, driver.path, try hasher.digest(driver, shared: true).hash]
        let base = URL(fileURLWithPath: directory.pathString, isDirectory: true)
        if let manifest = environment["CARGO_MANIFEST_DIR"] {
            let file = URL(fileURLWithPath: manifest, relativeTo: base).standardizedFileURL.appendingPathComponent("Cargo.toml")
            inputs += FileManager.default.fileExists(atPath: file.path)
                ? ["manifest", file.path, try hasher.digest(file).hash] : ["manifest", "none"]
        }
        if let (file, names) = Self.configuration(environment: environment, directory: directory) {
            // Both names in one directory make Clippy warn that it ignores the second.
            inputs += ["configuration", file.path, try hasher.digest(file).hash, names.joined(separator: ",")]
        } else {
            inputs += ["configuration", "none"]
        }
        for name in Self.environment.sorted() {
            inputs.append(environment[name].map { "\(name)=\($0)" } ?? "\(name) unset")
        }
        return inputs
    }

    /// The configuration file Clippy loads, and the configuration names in its directory: the first `.clippy.toml` or
    /// `clippy.toml` from `CLIPPY_CONF_DIR`, else the manifest directory, up to the root.
    static func configuration(environment: [String: String], directory: AbsolutePath) -> (URL, [String])? {
        let base = URL(fileURLWithPath: directory.pathString, isDirectory: true)
        let start = environment["CLIPPY_CONF_DIR"] ?? environment["CARGO_MANIFEST_DIR"] ?? "."
        var current = URL(fileURLWithPath: start, relativeTo: base).standardizedFileURL.resolvingSymlinksInPath()
        while true {
            let names = [".clippy.toml", "clippy.toml"].filter { name in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: current.appendingPathComponent(name).path, isDirectory: &isDirectory
                ) && !isDirectory.boolValue
            }
            if let first = names.first { return (current.appendingPathComponent(first).resolvingSymlinksInPath(), names) }
            guard current.path != "/" else { return nil }
            current = current.deletingLastPathComponent()
        }
    }

    /// Whether `text` enables a lint of Clippy's `cargo` group, which runs `cargo metadata` and reads every manifest of
    /// the workspace and its lockfile: no key could name those reads.
    /// rustc reads `-` in a command-line lint name as `_`, and flags join their lint (`-Wclippy::cargo`), so the match
    /// takes hyphens as underscores and needs no word boundary before `clippy`. It also refuses allowing these lints.
    static func refusesLints(_ text: String) -> Bool {
        guard text.contains("clippy") else { return false }
        let text = text.replacingOccurrences(of: "-", with: "_")
        return cargoLints.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let cargoLints = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "clippy\\s*::\\s*(cargo|cargo_common_metadata|multiple_crate_versions|wildcard_dependencies"
            + "|negative_feature_names|redundant_feature_names)\\b"
    )
}
