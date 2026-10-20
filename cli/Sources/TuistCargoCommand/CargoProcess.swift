import Foundation
import Path
import TuistProcess
import TuistServer

struct CargoProcess {
    let runner: CommandRunning

    func execute(_ executable: String, arguments: [String], environment: [String: String], directory: AbsolutePath) async throws {
        try await runner.runInheritingOutput(
            arguments: ["/usr/bin/env", executable] + arguments,
            environment: reportingEnvironment(environment),
            workingDirectory: directory
        )
    }

    func capture(
        _ executable: String,
        arguments: [String],
        environment: [String: String],
        directory: AbsolutePath
    ) async throws -> String {
        var data = Data()
        for try await event in runner.run(
            arguments: ["/usr/bin/env", executable] + arguments,
            environment: reportingEnvironment(environment),
            workingDirectory: directory
        ) {
            if case let .standardOutput(bytes) = event {
                guard data.count + bytes.count <= 64_000_000
                else { throw CargoReportError(message: "Cargo metadata exceeds 64 MB.") }
                data.append(contentsOf: bytes)
            }
        }
        guard let result = String(data: data, encoding: .utf8)
        else { throw CargoReportError(message: "Cargo metadata is not UTF-8.") }
        return result
    }

    private func reportingEnvironment(_ environment: [String: String]) -> [String: String] {
        guard environment["TUIST_CARGO_NATIVE"] == "1",
              let directory = environment["TUIST_CARGO_CACHE_REPORTS"] else { return environment }
        var environment = environment
        environment["TUIST_CARGO_CACHE_STATS_REPORT"] = URL(fileURLWithPath: directory)
            .appendingPathComponent("\(UUID().uuidString).json").path
        return environment
    }

    func executable(
        invocation: CargoInvocation,
        environment: [String: String],
        directory: AbsolutePath
    ) async throws -> (path: String, toolchain: String?) {
        if let configured = environment["TUIST_CARGO_EXECUTABLE"] { return (configured, nil) }
        let options = invocation.toolchain.map { ["--toolchain", $0] } ?? []
        do {
            let path = try await capture(
                "rustup",
                arguments: ["which"] + options + ["cargo"],
                environment: environment,
                directory: directory
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                let active = environment["RUSTUP_TOOLCHAIN"] == nil ? try? await capture(
                    "rustup",
                    arguments: ["show", "active-toolchain"],
                    environment: environment,
                    directory: directory
                ) : nil
                return (path, active?.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch { if invocation.toolchain != nil { throw error } }
        // A PATH shim may decorate back into Tuist. Only fall back to native binaries.
        let headers: Set<Data> = [
            Data([0x7F, 0x45, 0x4C, 0x46]),
            Data([0xCF, 0xFA, 0xED, 0xFE]),
            Data([0xCE, 0xFA, 0xED, 0xFE]),
            Data([0xCA, 0xFE, 0xBA, 0xBE]),
        ]
        for entry in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent("cargo")
            guard FileManager.default.isExecutableFile(atPath: candidate.path),
                  let file = try? FileHandle(forReadingFrom: candidate) else { continue }
            let magic = try? file.read(upToCount: 4)
            try? file.close()
            if let magic, headers.contains(magic) { return (candidate.path, nil) }
        }
        throw CargoReportError(
            message: "Cannot resolve a real Cargo executable. Set TUIST_CARGO_EXECUTABLE to its absolute path."
        )
    }

    static func ownExecutable() throws -> String {
        let name = CommandLine.arguments[0]
        if name.contains("/") { return URL(fileURLWithPath: name).standardizedFileURL.resolvingSymlinksInPath().path }
        for path in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let url = URL(fileURLWithPath: String(path)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url.resolvingSymlinksInPath().path }
        }
        throw CargoReportError(message: "Cannot resolve the Tuist executable for compiler observation.")
    }

    func workspace(
        executable: String,
        arguments: [String],
        directory: AbsolutePath,
        environment: [String: String]
    ) async -> (root: URL, target: URL) {
        let fallback = URL(fileURLWithPath: directory.pathString)
        guard let object = await packageMetadata(
            executable: executable, arguments: arguments, directory: directory, environment: environment
        ), let root = object["workspace_root"] as? String, let target = object["target_directory"] as? String else {
            return (fallback, fallback.appendingPathComponent("target"))
        }
        return (URL(fileURLWithPath: root), URL(fileURLWithPath: target))
    }

    func packageMetadata(
        executable: String,
        arguments: [String],
        directory: AbsolutePath,
        environment: [String: String]
    ) async -> [String: Any]? {
        var options = ["metadata", "--no-deps", "--offline", "--locked", "--format-version", "1"]
        for (index, value) in arguments.prefix(while: { $0 != "--" }).enumerated() {
            if ["--manifest-path", "--config"].contains(value), index + 1 < arguments.count { options += [
                value,
                arguments[index + 1],
            ] } else if value.hasPrefix("--manifest-path=") || value.hasPrefix("--config=") { options.append(value) }
        }
        guard let output = try? await capture(executable, arguments: options, environment: environment, directory: directory)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
    }
}
