import Foundation
import Path
import TuistCI
import TuistServer

struct CargoBuildOutcome {
    let finished: Date
    let failed: Bool

    static func test(_ result: CargoTestResult, compilations: [CargoCompilation]) -> Self? {
        // Tests can invoke Cargo themselves and append failed compiler rows after the outer build succeeded.
        if let finished = result.buildFinished { return Self(finished: finished, failed: false) }
        guard result.canReportBuildFailure, result.report == nil, compilations.contains(where: { $0.status == "failure" }) else {
            return nil
        }
        return Self(finished: result.finished, failed: true)
    }

    func compilations(_ rows: [CargoCompilation], started: Date) -> [CargoCompilation] {
        let duration = CargoCommandService.milliseconds(finished.timeIntervalSince(started))
        // Compiler start offsets and durations are rounded independently to milliseconds.
        return rows.filter {
            (0 ... duration).contains($0.startOffsetMs)
                && (0 ... duration - $0.startOffsetMs + 1).contains($0.durationMs)
        }
    }
}

struct CargoReporting {
    let process: CargoProcess
    let directory: AbsolutePath
    let environment: [String: String]
    let handle: String
    let serverURL: URL

    func metadata() async -> [String: Any] {
        let ci = CIController().ciInfo()
        var result: [String: Any] = ["is_ci": ci != nil]
        for (field, args) in [
            ("git_branch", ["rev-parse", "--abbrev-ref", "HEAD"]),
            ("git_commit_sha", ["rev-parse", "HEAD"]),
            ("git_remote_url_origin", ["remote", "get-url", "origin"]),
        ] {
            result[field] = try? await process.capture("git", arguments: args, environment: environment, directory: directory)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        result["ci_provider"] = ci.map { String(describing: $0.provider) }
        result["ci_run_id"] = ci?.runId
        result["ci_project_handle"] = ci?.projectHandle
        result["ci_host"] = ci?.host
        result["git_ref"] = environment["GITHUB_REF"] ?? environment["CI_COMMIT_REF_NAME"]
        result["rust_version"] = try? await process.capture(
            "rustc",
            arguments: ["--version"],
            environment: environment,
            directory: directory
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    func build(
        root: URL,
        started: Date,
        finished: Date,
        command: String,
        metadata: [String: Any],
        failed: Bool,
        testResult: CargoTestResult? = nil
    ) async {
        let events = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var remainingBytes = 40_000_000
        let compilations = events.filter { $0.pathExtension == "json" }.prefix(20000).compactMap { url -> CargoCompilation? in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000, size <= remainingBytes,
                  let data = try? Data(contentsOf: url) else { return nil }
            remainingBytes -= data.count
            return try? JSONDecoder().decode(CargoCompilation.self, from: data)
        }
        let outcome: CargoBuildOutcome
        if let testResult {
            guard let measured = CargoBuildOutcome.test(testResult, compilations: compilations) else {
                if environment["TUIST_DEBUG"] == "1" {
                    FileHandle.standardError
                        .write(Data("Tuist Cargo reporting: build phase was not measured; skipping build report.\n".utf8))
                }
                return
            }
            outcome = measured
        } else {
            outcome = CargoBuildOutcome(finished: finished, failed: failed)
        }
        let reportedCompilations = testResult?.buildFinished == nil
            ? compilations : outcome.compilations(compilations, started: started)
        guard let compilationData = try? JSONEncoder().encode(reportedCompilations),
              let rows = try? JSONSerialization.jsonObject(with: compilationData) else { return }
        var payload = metadata
        payload.merge(
            [
                "id": UUID().uuidString,
                "duration_ms": CargoCommandService.milliseconds(outcome.finished.timeIntervalSince(started)),
                "started_at": ISO8601DateFormatter().string(from: started),
                "status": outcome.failed ? "failure" : "success",
                "command": command,
                "contract_version": "1",
                "compilations": rows,
            ],
            uniquingKeysWith: { _, new in new }
        )
        if let cache = CargoCacheReport.read(root: root) { payload["cache"] = cache }
        await submit(payload, kind: "builds")
    }

    func tests(run: CargoNextestRun, metadata: [String: Any], failed: Bool) async {
        guard let current = CargoNextestRun.fingerprint(run.junitURL), current != run.previousReport,
              let report = try? NextestReport.read(run.junitURL) else { return }
        var payload = metadata
        payload.merge(
            [
                "id": UUID().uuidString,
                "build_system": "cargo",
                "duration": report.duration,
                "status": failed ? "failure" : "success",
                "test_modules": report.modules,
                "scheme": CargoNextestRun.scheme(label: environment["TUIST_SCHEME"]),
                "execution_mode": "parallel",
            ],
            uniquingKeysWith: { _, new in new }
        )
        if let inventory = run.inventory { payload["enumerated_tests"] = inventory.enumeration }
        if let shardID = run.shardID { payload["shard_plan_id"] = shardID; payload["shard_index"] = run.shardIndex }
        await submit(payload, kind: "tests")
    }

    func tests(report: CargoTestReport, metadata: [String: Any], failed: Bool) async {
        var payload = metadata
        let label = environment["TUIST_SCHEME"].flatMap { $0.isEmpty ? nil : $0 }
        payload.merge(
            [
                "id": UUID().uuidString,
                "build_system": "cargo",
                "duration": report.duration,
                "status": failed ? "failure" : "success",
                "test_modules": report.modules,
                "scheme": label.map { "cargo test · \($0)" } ?? "cargo test",
            ],
            uniquingKeysWith: { _, new in new }
        )
        await submit(payload, kind: "tests")
    }

    private func submit(_ payload: [String: Any], kind: String) async {
        do {
            try await CargoReportService().submit(
                JSONSerialization.data(withJSONObject: payload),
                fullHandle: handle,
                serverURL: serverURL,
                kind: kind
            )
        } catch {
            if environment["TUIST_DEBUG"] ==
                "1" { FileHandle.standardError.write(Data("Tuist Cargo reporting: \(error.localizedDescription)\n".utf8)) }
        }
    }
}

struct CargoNextestRun {
    static func scheme(label: String?) -> String {
        let label = label ?? "nextest"
        return label == "cargo test" || label.hasPrefix("cargo test · ") ? "cargo nextest run · \(label)" : label
    }

    let arguments: [String]
    let junitURL: URL
    let inventory: NextestInventory?
    let shardID: String?
    let shardIndex: Int?
    let previousReport: Data?

    static func fingerprint(_ url: URL) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        // Nextest's report UUID is in its header. Comparing a bounded prefix avoids deleting user reports.
        return try? file.read(upToCount: 1024)
    }
}
