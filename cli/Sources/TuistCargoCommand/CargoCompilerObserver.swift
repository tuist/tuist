import Foundation
import Path
import TuistProcess
import TuistServer

struct CargoCompilerObserver {
    let runner: CommandRunning

    func run(_ arguments: [String], environment: [String: String], directory: AbsolutePath) async throws {
        guard let compiler = arguments.first else { throw CargoReportError(message: "Missing compiler executable.") }
        let started = Date()
        let wrapper = environment["TUIST_CARGO_INNER_WRAPPER"].flatMap { $0.isEmpty ? nil : $0 }
        var executionError: Error?
        var diagnostics: [CargoDiagnostic] = []
        var pending = Data()
        do {
            for try await event in runner.run(
                arguments: ["/usr/bin/env", wrapper ?? compiler] + (wrapper == nil ? Array(arguments.dropFirst()) : arguments),
                environment: environment, workingDirectory: directory
            ) {
                switch event {
                case let .standardOutput(bytes): FileHandle.standardOutput.write(Data(bytes))
                case let .standardError(bytes):
                    FileHandle.standardError.write(Data(bytes))
                    pending.append(contentsOf: bytes)
                    if pending.count > 1_000_000 { pending.removeAll() }
                    diagnostics += Self.diagnostics(from: &pending, remaining: 100 - diagnostics.count)
                }
            }
        } catch { executionError = error }
        record(arguments, environment: environment, started: started, failed: executionError != nil, diagnostics: diagnostics)
        if let executionError { throw executionError }
    }

    private static func diagnostics(from pending: inout Data, remaining: Int) -> [CargoDiagnostic] {
        var result: [CargoDiagnostic] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: newline)
            pending.removeSubrange(...newline)
            guard result.count < remaining,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let level = json["level"] as? String, ["error", "warning"].contains(level),
                  let message = json["message"] as? String else { continue }
            let span = (json["spans"] as? [[String: Any]])?.first { $0["is_primary"] as? Bool == true }
            result.append(.init(
                severity: level,
                message: String(message.prefix(10000)),
                file: span?["file_name"] as? String,
                line: span?["line_start"] as? Int
            ))
        }
        return result
    }

    private func record(
        _ arguments: [String],
        environment: [String: String],
        started: Date,
        failed: Bool,
        diagnostics: [CargoDiagnostic]
    ) {
        guard let session = environment["TUIST_CARGO_SESSION"],
              let origin = environment["TUIST_CARGO_STARTED"].flatMap(Double.init),
              let source = arguments.dropFirst().first(where: { $0.hasSuffix(".rs") }),
              !arguments.contains("--print") else { return }
        func option(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        let dependencies = arguments.enumerated().compactMap { index, value -> String? in
            guard value == "--extern", index + 1 < arguments.count else { return nil }
            return arguments[index + 1].components(separatedBy: "=").first
        }
        let compilation = CargoCompilation(
            name: option("--crate-name") ?? "unknown", source: source,
            kind: arguments.contains("--test") ? "test" : option("--crate-type") ?? "lib",
            dependencies: Array(dependencies.prefix(5000)),
            startOffsetMs: CargoCommandService.milliseconds(started.timeIntervalSince1970 - origin),
            durationMs: CargoCommandService.milliseconds(Date().timeIntervalSince(started)),
            status: failed ? "failure" : "success", diagnostics: diagnostics
        )
        if let data = try? JSONEncoder().encode(compilation) {
            try? data.write(
                to: URL(fileURLWithPath: session).appendingPathComponent(UUID().uuidString + ".json"),
                options: .atomic
            )
        }
    }
}
