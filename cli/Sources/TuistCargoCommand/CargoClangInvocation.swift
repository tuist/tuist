import FileSystem
import Foundation
import Path
import TuistREAPI

extension CargoClangInvocation {
    static func configure(
        environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> [String: String] {
        #if os(macOS) && arch(arm64)
            guard let cache = environment["TUIST_CARGO_CACHE_DIR"],
                  !cache.contains(":"),
                  !environment.keys.contains(where: { $0 == "CC" || $0.hasPrefix("CC_") || $0.hasSuffix("_CC") }),
                  (environment["PATH"] ?? "").components(separatedBy: ":").allSatisfy({ $0.hasPrefix("/") }),
                  (environment["PATH"] ?? "").components(separatedBy: ":").map({
                      URL(fileURLWithPath: String($0)).appendingPathComponent("cc")
                  }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })?.path == "/usr/bin/cc"
            else { return environment }
            let path = try await process.capture(
                "/usr/bin/xcrun", arguments: ["--find", "clang"], environment: environment, directory: directory
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasSuffix("/XcodeDefault.xctoolchain/usr/bin/clang") else { return environment }
            let libraries = try await process.capture(
                "/usr/bin/otool", arguments: ["-L", path], environment: environment, directory: directory
            )
            guard libraries.split(separator: "\n").dropFirst().allSatisfy({
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("/usr/lib/")
            }) else { return environment }
            // A stable path avoids making cc-rs's rerun-if-env-changed invalidate every no-op build.
            let wrapper = URL(fileURLWithPath: cache).appendingPathComponent("wrappers/cc")
            let wrapperDirectory = CargoInvocation.shellQuote(wrapper.deletingLastPathComponent().path)
            let script = """
            #!/bin/sh
            TUIST_CARGO_CC_VISITED=${TUIST_CARGO_CC_VISITED:+$TUIST_CARGO_CC_VISITED:}$0
            export TUIST_CARGO_CC_VISITED
            TUIST_CARGO_CC_REMAINING=${PATH-}
            TUIST_CARGO_CC_PATH=
            TUIST_CARGO_CC_SEPARATOR=
            TUIST_CARGO_CC_SEARCH_PATH=
            TUIST_CARGO_CC_SEARCH_SEPARATOR=
            TUIST_CARGO_CC_COMPILER=
            while :; do
              case "$TUIST_CARGO_CC_REMAINING" in
                *:*)
                  TUIST_CARGO_CC_ENTRY=${TUIST_CARGO_CC_REMAINING%%:*}
                  TUIST_CARGO_CC_REMAINING=${TUIST_CARGO_CC_REMAINING#*:}
                  TUIST_CARGO_CC_MORE=1
                  ;;
                *) TUIST_CARGO_CC_ENTRY=$TUIST_CARGO_CC_REMAINING; TUIST_CARGO_CC_MORE=0 ;;
              esac
              if [ "$TUIST_CARGO_CC_ENTRY" != \(wrapperDirectory) ] &&
                 ! [ "${TUIST_CARGO_CC_ENTRY:-.}" -ef \(wrapperDirectory) ]; then
                TUIST_CARGO_CC_PATH=$TUIST_CARGO_CC_PATH$TUIST_CARGO_CC_SEPARATOR$TUIST_CARGO_CC_ENTRY
                TUIST_CARGO_CC_SEPARATOR=:
                TUIST_CARGO_CC_CANDIDATE=${TUIST_CARGO_CC_ENTRY:-.}/cc
                # Retained wrapper generations share exclusions, but keep their directories for helpers.
                TUIST_CARGO_CC_PREVIOUS=$TUIST_CARGO_CC_VISITED
                TUIST_CARGO_CC_ALIAS=0
                while [ -n "$TUIST_CARGO_CC_PREVIOUS" ]; do
                  TUIST_CARGO_CC_IDENTITY=${TUIST_CARGO_CC_PREVIOUS%%:*}
                  if [ "$TUIST_CARGO_CC_CANDIDATE" -ef "$TUIST_CARGO_CC_IDENTITY" ]; then
                    TUIST_CARGO_CC_ALIAS=1
                    break
                  fi
                  case "$TUIST_CARGO_CC_PREVIOUS" in
                    *:*) TUIST_CARGO_CC_PREVIOUS=${TUIST_CARGO_CC_PREVIOUS#*:} ;;
                    *) break ;;
                  esac
                done
                if ! [ "$TUIST_CARGO_CC_CANDIDATE" -ef \(CargoInvocation.shellQuote(wrapper.path)) ] &&
                   [ "$TUIST_CARGO_CC_ALIAS" -eq 0 ]; then
                  case "$TUIST_CARGO_CC_ENTRY" in
                    /*) TUIST_CARGO_CC_SEARCH_ENTRY=$TUIST_CARGO_CC_ENTRY ;;
                    *) TUIST_CARGO_CC_SEARCH_ENTRY=./$TUIST_CARGO_CC_ENTRY ;;
                  esac
                  TUIST_CARGO_CC_SEARCH_PATH=$TUIST_CARGO_CC_SEARCH_PATH$TUIST_CARGO_CC_SEARCH_SEPARATOR$TUIST_CARGO_CC_SEARCH_ENTRY
                  TUIST_CARGO_CC_SEARCH_SEPARATOR=:
                  if [ -z "$TUIST_CARGO_CC_COMPILER" ] && [ -f "$TUIST_CARGO_CC_CANDIDATE" ] &&
                     [ -x "$TUIST_CARGO_CC_CANDIDATE" ]; then
                    TUIST_CARGO_CC_COMPILER=$TUIST_CARGO_CC_SEARCH_ENTRY/cc
                  fi
                fi
              fi
              if [ "$TUIST_CARGO_CC_MORE" -eq 0 ]; then break; fi
            done
            if [ -z "$TUIST_CARGO_CC_SEARCH_SEPARATOR" ]; then
              printf '%s\\n' 'cc: command not found' >&2
              exit 127
            fi
            if [ -z "$TUIST_CARGO_CC_COMPILER" ]; then
              PATH=$TUIST_CARGO_CC_SEARCH_PATH
              export PATH
              exec /usr/bin/env cc "$@"
            fi
            PATH=$TUIST_CARGO_CC_PATH
            export PATH
            if [ "$TUIST_CARGO_CC_COMPILER" != /usr/bin/cc ]; then
              exec /usr/bin/env -u BASH_ENV /bin/bash -c '
                if [ "$1" = x ]; then export BASH_ENV="$2"; fi
                export SHLVL="$3"
                shift 3
                exec -a cc -- "$@"
              ' -- "${BASH_ENV+x}" "${BASH_ENV-}" "${SHLVL-0}" "$TUIST_CARGO_CC_COMPILER" "$@"
            fi
            if [ -n "${TUIST_CARGO_CACHE_REMOTE_URL:-}" ]; then
              for TUIST_CARGO_CC_INPUT do
                case "$TUIST_CARGO_CC_INPUT" in
                  *.c)
                    if TUIST_CARGO_CC_SIZE=$(/usr/bin/stat -L -f %z -- "$TUIST_CARGO_CC_INPUT" 2>/dev/null); then
                      if [ -n "$TUIST_CARGO_CC_SIZE" ] && [ "$TUIST_CARGO_CC_SIZE" -lt \(minimumRemoteSourceBytes) ]; then
                        exec /usr/bin/cc "$@"
                      fi
                    fi
                    ;;
                esac
              done
            fi
            exec \(CargoInvocation.shellQuote(try CargoProcess.ownExecutable())) cargo __native /usr/bin/cc "$@"

            """
            try FileManager.default.createDirectory(at: wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
            try script.write(to: wrapper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
            var result = environment
            result["PATH"] = wrapper.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
            result["TUIST_CARGO_CACHE_CLANG"] = path
            return result
        #else
            return environment
        #endif
    }
}

/// Cache C compiler actions inside build scripts, never execution of the scripts themselves.
struct CargoClangInvocation: CargoCacheAction {
    let arguments: [String]
    let environment: [String: String]
    let directory: AbsolutePath
    let compiler: URL
    let output: URL
    let files: [String]
    let name: String
    let probeArguments: [String]
    let process: CargoProcess
    let inputHasher: CargoInputHasher
    var inputs: [URL] = []
    var probeDigest = REAPI.emptyBlob
    var key = REAPI.emptyBlob

    private static let minimumRemoteSourceBytes = 32768
    var cacheVersion: String { "tuist-swift-cargo-clang-v3" }
    var kind: String { "compiler" }

    static func prepare(
        _ arguments: [String], environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> CargoClangInvocation? {
        #if os(macOS) && arch(arm64)
            guard environment["TUIST_CARGO_CACHE_DIR"] != nil, arguments.first == "/usr/bin/cc",
                  let compiler = environment["TUIST_CARGO_CACHE_CLANG"],
                  !environment.keys.contains(where: {
                      ["DYLD_", "LD_", "CCC_", "CC_PRINT_", "CC_LOG_", "CLANG_"].contains(where: $0.hasPrefix)
                          || $0 == "AS_SECURE_LOG_FILE"
                  }),
                  let parsed = parse(arguments) else { return nil }
            let base = URL(fileURLWithPath: directory.pathString)
            let destination = URL(fileURLWithPath: parsed.output, relativeTo: base).standardizedFileURL
            guard destination.pathExtension == "o" else { return nil }
            if environment["TUIST_CARGO_CACHE_REMOTE_URL"] != nil {
                let source = URL(fileURLWithPath: parsed.source, relativeTo: base).resolvingSymlinksInPath()
                // Small translation units often compile faster than remote discovery and transfer.
                guard (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) >= minimumRemoteSourceBytes else {
                    return nil
                }
            }
            var candidate = CargoClangInvocation(
                arguments: arguments, environment: environment, directory: directory,
                compiler: URL(fileURLWithPath: compiler), output: destination.deletingLastPathComponent(),
                files: [destination.lastPathComponent], name: "clang " + URL(fileURLWithPath: parsed.source).lastPathComponent,
                probeArguments: parsed.probe, process: process,
                inputHasher: CargoInputHasher(sessionDirectory: environment["TUIST_CARGO_SESSION"]
                    .map { URL(fileURLWithPath: $0) })
            )
            let probe = try await candidate.discover()
            candidate.inputs = probe.inputs
            candidate.probeDigest = probe.digest
            candidate.key = try candidate.fingerprint()
            return candidate
        #else
            return nil
        #endif
    }

    static func parse(_ arguments: [String]) -> (source: String, output: String, probe: [String])? {
        guard !arguments.contains(where: { $0.hasPrefix("@") }) else { return nil }
        let flags: Set<String> = [
            "-w", "-pthread", "-fPIC", "-fpic", "-ffunction-sections", "-fdata-sections", "-fmerge-all-constants",
            "-fvisibility=hidden", "-fvisibility=default", "-fno-strict-aliasing", "-fno-omit-frame-pointer",
            "-fno-common", "-fcommon", "-fno-builtin", "-fwrapv", "-fno-strict-overflow",
            "-fstack-protector", "-fstack-protector-strong", "-fno-stack-protector", "-fno-exceptions",
            "-g", "-g0", "-g1", "-g2", "-g3", "-gfull", "-gdwarf-2", "-gdwarf-3", "-gdwarf-4", "-gdwarf-5",
        ]
        var source: String?
        var output: String?
        var compiling = false
        var probe: [String] = []
        var index = 1
        while index < arguments.count {
            let value = arguments[index]
            if value == "-o" {
                guard output == nil, index + 1 < arguments.count else { return nil }
                output = arguments[index + 1]
                index += 2
                continue
            }
            if value == "-c" {
                guard !compiling else { return nil }
                compiling = true
            } else if ["-I", "-isystem", "-D", "-U", "-isysroot"].contains(value) {
                guard index + 1 < arguments.count else { return nil }
                probe += [value, arguments[index + 1]]
                index += 2
                continue
            } else if !value.hasPrefix("-"), value.hasSuffix(".c"), !value.hasPrefix("@") {
                guard source == nil else { return nil }
                source = value
            } else if !flags.contains(value),
                      value.range(
                          of: "^(-[IDU].+|-O[0-3sz]|-W(?![apl],)[A-Za-z0-9_=-]+|-std=(c|gnu)(89|90|99|1x|11|17|18|2x|23)|--target=arm64-apple-macosx[0-9.]*|-mmacosx-version-min=[0-9.]+)$",
                          options: .regularExpression
                      ) == nil { return nil }
            if value != "-c" { probe.append(value) }
            index += 1
        }
        guard compiling, let source, let output, !output.isEmpty else { return nil }
        return (source, output, probe)
    }

    func fingerprint() throws -> REAPI.Digest {
        var values = [cacheVersion, directory.pathString, ProcessInfo.processInfo.operatingSystemVersionString, probeDigest.hash]
        values += arguments
        values += environment.sorted { $0.key < $1.key }.filter {
            !CargoCacheInvocation.ignoredEnvironment.contains($0.key) && !$0.key.hasPrefix("TUIST_")
        }.map { "\($0.key)=\($0.value)" }
        var budget: Int64 = 500_000_000
        for file in inputs + [compiler] {
            let resolved = file.resolvingSymlinksInPath()
            let digest = try inputHasher.digest(resolved, shared: true)
            guard digest.sizeBytes <= budget else { throw CargoCacheInvocation.CacheError.unsupported }
            budget -= digest.sizeBytes
            values += [file.path, resolved.path, digest.hash, String(digest.sizeBytes)]
        }
        return REAPI.digest(try JSONEncoder().encode(values))
    }

    func validateDependencies(restoring _: Bool) async throws {
        let probe = try await discover()
        guard probe.inputs == inputs, probe.digest == probeDigest else { throw CargoCacheInvocation.CacheError.unsupported }
    }

    func certifyOutputs(metadataOnly _: Bool) throws {}
    func outputFiles() throws -> [String] { files }
    func acceptsOutput(_ file: String) -> Bool { files.contains(file) }

    private func discover() async throws -> (inputs: [URL], digest: REAPI.Digest) {
        let plan = try await process.captureOutput(
            arguments[0], arguments: Array(arguments.dropFirst()) + ["-###"], environment: environment, directory: directory
        )
        guard plan.stdout.isEmpty, let driver = String(data: plan.stderr, encoding: .utf8),
              driver.hasPrefix("Apple clang version"), !driver.contains("Configuration file:"),
              driver.contains("\"\(compiler.path)\" \"-cc1\""),
              let range = driver.range(of: "\"-isysroot\" \"[^\"\\\\]+\"", options: .regularExpression)
        else { throw CargoCacheInvocation.CacheError.unsupported }
        let sdk = String(driver[range]).dropFirst("\"-isysroot\" \"".count).dropLast()
        let settings = URL(fileURLWithPath: String(sdk)).appendingPathComponent("SDKSettings.json").resolvingSymlinksInPath()
        return try await FileSystem().runInTemporaryDirectory(prefix: "tuist-cargo-clang") { temporary in
            let dependencies = URL(fileURLWithPath: temporary.pathString).appendingPathComponent("inputs.d")
            let expanded = try await process.captureOutput(
                arguments[0], arguments: probeArguments + ["-E", "-dD", "-MD", "-MF", dependencies.path, "-MT", "tuist-inputs"],
                environment: environment, directory: directory
            )
            guard expanded.stderr.isEmpty, let text = String(data: expanded.stdout, encoding: .utf8) else {
                throw CargoCacheInvocation.CacheError.unsupported
            }
            try Self.validateExpandedSource(text)
            guard (try dependencies.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 2_000_000 else {
                throw CargoCacheInvocation.CacheError.unsupported
            }
            let names = try CargoCacheInvocation.dependencies(String(contentsOf: dependencies, encoding: .utf8))
            guard !names.isEmpty, names.count <= 10000 else { throw CargoCacheInvocation.CacheError.unsupported }
            let base = URL(fileURLWithPath: directory.pathString)
            let inputs = Set(names.map { URL(fileURLWithPath: $0, relativeTo: base).standardizedFileURL } + [settings])
                .sorted { $0.path < $1.path }
            return (inputs, REAPI.digest(plan.stderr + expanded.stdout))
        }
    }

    /// Only empty asm templates or single identifier strings are admitted. This includes Darwin
    /// declaration labels, but cannot form an assembler directive or interpolate an operand.
    static func validateExpandedSource(_ text: String) throws {
        let bytes = Array(text.utf8)
        var index = 0
        var lineStart = true
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 10 { lineStart = true; index += 1; continue }
            if lineStart {
                if isWhitespace(byte) { index += 1; continue }
                if byte == 35 {
                    while index < bytes.count, bytes[index] != 10 {
                        index += 1
                    }
                    continue
                }
                lineStart = false
            }
            if byte >= 48, byte <= 57 {
                // C23 separators are part of a preprocessing number, not character literals.
                while index < bytes.count, isIdentifier(bytes[index]) || bytes[index] == 39 || bytes[index] == 46 {
                    index += 1
                }
                continue
            }
            if byte == 34 || byte == 39 {
                let quote = byte
                index += 1
                while index < bytes.count {
                    let value = bytes[index]
                    index += 1
                    if value == 92 { index += 1 } else if value == quote { break }
                }
                continue
            }
            guard isIdentifier(byte) else { index += 1; continue }
            let start = index
            while index < bytes.count, isIdentifier(bytes[index]) {
                index += 1
            }
            guard byte == 97 || byte == 95 else { continue }
            let token = bytes[start ..< index]
            if token.elementsEqual("asm".utf8) || token.elementsEqual("__asm".utf8) || token.elementsEqual("__asm__".utf8) {
                var cursor = index
                while cursor < bytes.count, isWhitespace(bytes[cursor]) {
                    cursor += 1
                }
                let qualifierStart = cursor
                while cursor < bytes.count, isIdentifier(bytes[cursor]) {
                    cursor += 1
                }
                if cursor != qualifierStart {
                    let qualifier = bytes[qualifierStart ..< cursor]
                    guard qualifier.elementsEqual("volatile".utf8) || qualifier.elementsEqual("__volatile".utf8)
                        || qualifier.elementsEqual("__volatile__".utf8)
                    else { throw CargoCacheInvocation.CacheError.unsupported }
                    while cursor < bytes.count, isWhitespace(bytes[cursor]) {
                        cursor += 1
                    }
                }
                guard cursor < bytes.count, bytes[cursor] == 40 else { throw CargoCacheInvocation.CacheError.unsupported }
                cursor += 1
                while cursor < bytes.count, isWhitespace(bytes[cursor]) {
                    cursor += 1
                }
                guard cursor < bytes.count, bytes[cursor] == 34 else { throw CargoCacheInvocation.CacheError.unsupported }
                repeat {
                    cursor += 1
                    while cursor < bytes.count, isIdentifier(bytes[cursor]) || bytes[cursor] == 36 {
                        cursor += 1
                    }
                    guard cursor < bytes.count, bytes[cursor] == 34 else {
                        throw CargoCacheInvocation.CacheError.unsupported
                    }
                    cursor += 1
                    while cursor < bytes.count, isWhitespace(bytes[cursor]) {
                        cursor += 1
                    }
                } while cursor < bytes.count && bytes[cursor] == 34
                guard cursor < bytes.count, bytes[cursor] == 58 || bytes[cursor] == 41 else {
                    throw CargoCacheInvocation.CacheError.unsupported
                }
            }
        }
    }
}

private func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 32 || (byte >= 9 && byte <= 13)
}

private func isIdentifier(_ byte: UInt8) -> Bool {
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 95
}
