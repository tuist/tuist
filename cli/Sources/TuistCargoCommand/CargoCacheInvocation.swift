import Foundation
import Path
import TuistREAPI

struct CargoCacheInvocation {
    let arguments: [String]
    let environment: [String: String]
    let directory: AbsolutePath
    let package: URL
    let compiler: URL
    let launcher: URL
    let toolchain: URL
    let output: URL
    let name: String
    let files: [String]
    let key: REAPI.Digest
    let inputHasher: CargoInputHasher

    static let keyVersion = "tuist-swift-cargo-cache-v2"
    static let ignoredEnvironment = Set([
        "RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WRAPPER", "CARGO_MAKEFLAGS", "MAKEFLAGS", "MFLAGS", "CI",
        "SHLVL", "OLDPWD", "_", "TERM_SESSION_ID", "INVOCATION_ID",
    ])
    static let ignoredEnvironmentPrefixes = [
        "TUIST_", "GITHUB_", "GITLAB_", "BUILDKITE_", "CIRCLE_", "CI_", "RUNNER_", "ACTIONS_", "TRAVIS_", "TEAMCITY_",
    ]

    static func prepare(
        _ arguments: [String], environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> CargoCacheInvocation? {
        guard environment["TUIST_CARGO_CACHE_DIR"] != nil,
              environment["TUIST_CARGO_INNER_WRAPPER"] == nil,
              environment["OUT_DIR"] == nil,
              environment["RUSTC_WORKSPACE_WRAPPER"].map(\.isEmpty) ?? true,
              !arguments.contains(where: {
                  $0.hasPrefix("@") || $0.hasPrefix("-Z") || $0.hasPrefix("--extern")
                      || $0.hasPrefix("--print") || $0.hasPrefix("--remap-path-prefix")
                      || $0.hasPrefix("--sysroot") || $0.hasPrefix("--target")
                      || $0 == "--test" || $0 == "-o"
              }),
              let executable = arguments.first, URL(fileURLWithPath: executable).lastPathComponent == "rustc",
              let manifest = environment["CARGO_MANIFEST_DIR"],
              let name = option("--crate-name", in: arguments),
              let kind = option("--crate-type", in: arguments), ["lib", "rlib"].contains(kind),
              let emit = option("--emit", in: arguments),
              Set(emit.split(separator: ",").map(String.init)) == Set(["dep-info", "metadata", "link"]),
              let out = option("--out-dir", in: arguments),
              let source = arguments.dropFirst().first(where: { $0.hasSuffix(".rs") }),
              !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        else { return nil }
        let searches = arguments.enumerated().compactMap { index, value -> String? in
            if value == "-L", index + 1 < arguments.count { return arguments[index + 1] }
            return value.hasPrefix("-L") ? String(value.dropFirst(2)) : nil
        }
        guard searches.allSatisfy({ $0.hasPrefix("dependency=") }) else { return nil }
        let codegen = arguments.enumerated().compactMap { index, value -> String? in
            if value == "-C", index + 1 < arguments.count { return arguments[index + 1] }
            return value.hasPrefix("-C") ? String(value.dropFirst(2)) : nil
        }
        let allowed = Set([
            "embed-bitcode", "debuginfo", "metadata", "extra-filename", "opt-level", "debug-assertions",
            "overflow-checks", "codegen-units", "panic", "strip", "target-cpu", "target-feature", "split-debuginfo",
        ])
        guard codegen.allSatisfy({ allowed.contains(String($0.prefix { $0 != "=" })) && $0 != "target-cpu=native" })
        else { return nil }
        if let split = codegen.last(where: { $0.hasPrefix("split-debuginfo=") }),
           !["split-debuginfo=off", "split-debuginfo=unpacked"].contains(split) { return nil }
        let suffix = codegen.first(where: { $0.hasPrefix("extra-filename=") }).map { String($0.dropFirst(15)) } ?? ""
        guard suffix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        let package = URL(fileURLWithPath: manifest).standardizedFileURL
        let cargoHome = URL(fileURLWithPath: environment["CARGO_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cargo").path)
        let registry = cargoHome.appendingPathComponent("registry/src").standardizedFileURL
        guard package.deletingLastPathComponent().deletingLastPathComponent() == registry,
              URL(fileURLWithPath: source, relativeTo: URL(fileURLWithPath: directory.pathString)).standardizedFileURL.path
              .hasPrefix(package.path + "/") else { return nil }
        let sysroot = try await process.capture(
            executable, arguments: ["--print", "sysroot"], environment: environment, directory: directory
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sysroot.hasPrefix("/") else { return nil }
        let toolchain = URL(fileURLWithPath: sysroot).standardizedFileURL
        let compiler = toolchain.appendingPathComponent("bin/rustc")
        guard let launcher = resolve(executable, environment: environment, directory: directory) else { return nil }
        if launcher != compiler.resolvingSymlinksInPath() {
            guard environment["RUSTUP_TOOLCHAIN"].map({ !$0.isEmpty }) == true,
                  launcher == resolve("rustup", environment: environment, directory: directory) else { return nil }
        }
        let files = ["lib\(name)\(suffix).rlib", "lib\(name)\(suffix).rmeta", "\(name)\(suffix).d"]
        let candidate = CargoCacheInvocation(
            arguments: arguments, environment: environment, directory: directory, package: package,
            compiler: compiler, launcher: launcher, toolchain: toolchain,
            output: URL(fileURLWithPath: out).standardizedFileURL,
            name: name, files: files, key: REAPI.emptyBlob, inputHasher: CargoInputHasher()
        )
        return CargoCacheInvocation(
            arguments: arguments, environment: environment, directory: directory, package: package,
            compiler: compiler, launcher: launcher, toolchain: toolchain, output: candidate.output, name: name, files: files,
            key: try candidate.fingerprint(), inputHasher: candidate.inputHasher
        )
    }

    func fingerprint() throws -> REAPI.Digest {
        var inputs = [Self.keyVersion, directory.pathString]
        inputs += keyArguments
        inputs += environment.sorted { $0.key < $1.key }.filter { !Self.isIgnored($0.key) }.map { "\($0.key)=\($0.value)" }
        var budget = 2_000_000_000
        inputs += try snapshot(package, budget: &budget, inspectSources: true)
        inputs += try snapshot(toolchain.appendingPathComponent("lib"), budget: &budget)
        for executable in Set([compiler.resolvingSymlinksInPath(), launcher]).sorted(by: { $0.path < $1.path }) {
            let digest = try inputHasher.digest(executable)
            inputs += [executable.path, digest.hash, String(digest.sizeBytes)]
        }
        return REAPI.digest(try JSONEncoder().encode(inputs))
    }

    func acceptsOutput(_ file: String) -> Bool {
        if files.contains(file) { return true }
        let prefix = String(files[2].dropLast(2)) + "."
        return file.hasPrefix(prefix) && ["o", "dwo", "dwp"].contains(URL(fileURLWithPath: file).pathExtension)
            && file.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    func outputFiles() throws -> [String] {
        let additional = try FileManager.default.contentsOfDirectory(atPath: output.path)
            .filter { !files.contains($0) && acceptsOutput($0) }.sorted()
        guard files.count + additional.count <= 128 else { throw CacheError.unsupported }
        return files + additional
    }

    private var keyArguments: [String] {
        var result: [String] = []
        var seen = false
        var index = 0
        while index < arguments.count {
            let parts = arguments[index].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let option = parts.first ?? ""
            guard option == "--diagnostic-width" else {
                result.append(arguments[index]); index += 1; continue
            }
            let value = parts.count == 2 ? parts[1] : (index + 1 < arguments.count ? arguments[index + 1] : "")
            guard !seen, !value.hasPrefix("-"), let width = Int(value, radix: 10), width >= 0 else { return arguments }
            seen = true
            index += parts.count == 2 ? 1 : 2
        }
        return result
    }

    func validateDependencies() throws {
        let path = output.appendingPathComponent(files[2])
        guard (try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 2_000_000 else {
            throw CacheError.unsupported
        }
        let text = try String(contentsOf: path, encoding: .utf8)
        guard !text.split(separator: "\n").contains(where: { line in
            guard line.hasPrefix("# env-dep:") else { return false }
            return Self.isIgnored(String(line.dropFirst(10).prefix { $0 != "=" }))
        }) else { throw CacheError.unsupported }
        let dependencies = try Self.dependencies(text)
        guard !dependencies.isEmpty, dependencies.allSatisfy({ dependency in
            let file = URL(fileURLWithPath: dependency, relativeTo: URL(fileURLWithPath: directory.pathString))
                .standardizedFileURL
            return file.path.hasPrefix(package.path + "/")
        }) else { throw CacheError.unsupported }
    }

    static func dependencies(_ text: String) throws -> [String] {
        var result: [String] = []
        for line in text.replacingOccurrences(of: "\\\n", with: " ").split(separator: "\n") where !line.hasPrefix("#") {
            var escaped = false
            var separator: String.SubSequence.Index?
            for index in line.indices {
                let character = line[index]
                if !escaped, character == ":" { separator = index; break }
                escaped = !escaped && character == "\\"
            }
            guard let separator else { throw CacheError.unsupported }
            var token = ""
            escaped = false
            for character in line[line.index(after: separator)...] {
                if escaped {
                    token.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character.isWhitespace {
                    if !token.isEmpty { result.append(token); token = "" }
                } else {
                    token.append(character)
                }
            }
            guard !escaped else { throw CacheError.unsupported }
            if !token.isEmpty { result.append(token) }
        }
        return result
    }

    private func snapshot(_ root: URL, budget: inout Int, inspectSources: Bool = false) throws -> [String] {
        var failed = false
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let entries = FileManager.default.enumerator(
                  at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                  errorHandler: { _, _ in failed = true; return false }
              ) else { throw CacheError.unsupported }
        var files: [(file: URL, digest: REAPI.Digest)] = []
        for case let file as URL in entries {
            let properties = try file.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            if properties.isSymbolicLink == true {
                let target = file.resolvingSymlinksInPath()
                guard !inspectSources, target.path.hasPrefix(toolchain.path + "/"),
                      try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                else {
                    throw CacheError.unsupported
                }
                files.append((target, try inputHasher.digest(target)))
            }
            if properties.isDirectory == true { continue }
            let content = file.resolvingSymlinksInPath()
            let regular = try content.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard files.count < 10000, regular.isRegularFile == true, let size = regular.fileSize,
                  size <= budget else { throw CacheError.unsupported }
            budget -= size
            let digest: REAPI.Digest
            if inspectSources, file.pathExtension == "rs" {
                guard size <= 2_000_000 else { throw CacheError.unsupported }
                digest = try inputHasher.sourceDigest(content) { data in
                    guard let text = String(data: data, encoding: .utf8), text.range(
                        of: "\\b(asm|global_asm|link|link_args|extern|include|concat|concat_idents)\\b",
                        options: .regularExpression
                    ) == nil else { throw CacheError.unsupported }
                }
            } else {
                digest = try inputHasher.digest(content)
            }
            files.append((file, digest))
        }
        guard !failed else { throw CacheError.unsupported }
        return files.sorted { $0.file.path < $1.file.path }.flatMap {
            [$0.file.path, $0.digest.hash, String($0.digest.sizeBytes)]
        }
    }

    private static func resolve(_ executable: String, environment: [String: String], directory: AbsolutePath) -> URL? {
        let base = URL(fileURLWithPath: directory.pathString, isDirectory: true)
        let candidates = executable.contains("/") ? [URL(fileURLWithPath: executable, relativeTo: base)] :
            (environment["PATH"] ?? "").components(separatedBy: ":").map {
                URL(fileURLWithPath: $0.isEmpty ? "." : $0, relativeTo: base).appendingPathComponent(executable)
            }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })?
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isIgnored(_ name: String) -> Bool {
        ignoredEnvironment.contains(name) || ignoredEnvironmentPrefixes.contains(where: name.hasPrefix)
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        if let index = arguments.firstIndex(of: name), index + 1 < arguments.count { return arguments[index + 1] }
        return arguments.first(where: { $0.hasPrefix(name + "=") }).map { String($0.dropFirst(name.count + 1)) }
    }

    enum CacheError: Error { case unsupported }
}
