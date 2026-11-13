import Foundation
import Path
import TuistAlert
import TuistCI
import TuistGit
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
    /// Whether test runs collect code coverage (`tuist.toml`'s `[test_insights.coverage] upload`, or
    /// `TUIST_COVERAGE_UPLOAD`).
    var uploadsCoverage = false

    func metadata() async -> [String: Any] {
        let ci = CIController().ciInfo()
        var result: [String: Any] = ["is_ci": ci != nil]
        // Concurrently: the build waits for none of them, but each costs a process start.
        func capture(_ executable: String, _ arguments: [String]) async -> String? {
            try? await process.capture(executable, arguments: arguments, environment: environment, directory: directory)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // One `rev-parse` answers both: the commit, then the branch.
        async let revisions = capture("git", ["rev-parse", "HEAD", "--abbrev-ref", "HEAD"])
        async let origin = capture("git", ["remote", "get-url", "origin"])
        let lines = await revisions?.split(separator: "\n").map(String.init) ?? []
        result["git_branch"] = lines.count == 2 ? lines[1] : nil
        result["git_commit_sha"] = lines.count == 2 ? lines[0] : nil
        result["git_remote_url_origin"] = await origin
        result["ci_provider"] = ci.map { String(describing: $0.provider) }
        result["ci_run_id"] = ci?.runId
        result["ci_project_handle"] = ci?.projectHandle
        result["ci_host"] = ci?.host
        result["git_ref"] = environment["GITHUB_REF"] ?? environment["CI_COMMIT_REF_NAME"]
        return result
    }

    /// `rustc --version`, for sessions that did not resolve the toolchain's identity, whose `-vV` starts with it.
    func rustVersion() async -> String? {
        try? await process.capture("rustc", arguments: ["--version"], environment: environment, directory: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Cargo did not previously accept custom_metadata. Wait for cluster-wide support even for small maps.
        let metadataLimit = await BuildMetadata.discoverLimit(serverURL: serverURL)
        payload["custom_metadata"] = buildMetadata(limit: metadataLimit)
        if metadataLimit > 20, payload["custom_metadata"] == nil {
            AlertController.current.warning(.alert("Cargo build metadata is invalid and was omitted from the report."))
        }
        if let cache = CargoCacheReport.read(root: root) {
            payload["cache"] = cache
            if environment["TUIST_DEBUG"] == "1",
               let tasks = (cache["details"] as? [String: Any])?["tasks"] as? [[String: Any]]
            {
                let lines = tasks.map { "Tuist Cargo cache: \($0["status"] ?? "") \($0["kind"] ?? "") \($0["name"] ?? "")\n" }
                FileHandle.standardError.write(Data(lines.sorted().joined().utf8))
            }
        }
        await submit(payload, kind: "builds")
    }

    func buildMetadata(limit: Int) -> [String: Any]? {
        guard limit > 20 else { return nil }
        let tags = (environment["TUIST_BUILD_TAGS"] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let explicit = BuildMetadata.explicitValues(environment: environment)
        guard tags.count <= 50, explicit.count <= limit,
              tags.allSatisfy({ $0.count <= 50 && $0.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil }),
              explicit.allSatisfy({ $0.key.count <= 50 && $0.value.count <= 500 })
        else { return nil }
        return [
            "tags": tags,
            "values": BuildMetadata.merge(
                explicit: explicit,
                observations: BuildMetadata.observations(environment: environment),
                limit: limit
            ),
        ]
    }

    func tests(run: CargoNextestRun, metadata: [String: Any], failed: Bool, coverage: CargoCoverage.Report? = nil) async {
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
        await submitTests(payload, coverage: coverage)
    }

    func tests(
        report: CargoTestReport, metadata: [String: Any], failed: Bool, shardID: String? = nil, shardIndex: Int? = nil,
        coverage: CargoCoverage.Report? = nil
    ) async {
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
        if let shardID { payload["shard_plan_id"] = shardID; payload["shard_index"] = shardIndex }
        await submitTests(payload, coverage: coverage)
    }

    /// Submits a test run with what it says about coverage: whether it was set up to collect it, and, when it was,
    /// the commit's Git history (uploaded before the run, its file listing after), the tests a narrowed run ran,
    /// the coverage, inline or uploaded first when large, and the evidence.
    private func submitTests(_ payload: [String: Any], coverage: CargoCoverage.Report?) async {
        var payload = payload
        payload["coverage_enabled"] = coverage?.enabled ?? false
        guard let coverage, coverage.enabled else { return await submit(payload, kind: "tests") }
        let git = GitController()
        let history: CollectedGitHistory?
        if let gitInfo = try? await git.gitInfo(workingDirectory: directory) {
            history = await GitHistoryService().publish(
                gitInfo: gitInfo, workingDirectory: directory, fullHandle: handle, serverURL: serverURL, coverage: true
            )
        } else {
            history = nil
        }
        if let history {
            let fields: [String: Any?] = [
                "base_branch": history.payload.baseBranch,
                "merge_base_sha": history.payload.mergeBaseSHA,
                "is_pull_request": history.payload.isPullRequest,
                "pull_request_number": history.payload.pullRequestNumber,
                "git_object_format": history.payload.objectFormat,
                "history_source": history.payload.source,
                "history_fallback_reason": history.payload.fallbackReason,
                "git_dirty": history.payload.dirty,
                // On a pull request's merge checkout, the commit the history and the listing describe.
                "git_commit_sha": history.history.headSHA.isEmpty ? nil : history.history.headSHA,
                "git_branch": history.branch,
            ]
            for case let (key, value?) in fields {
                payload[key] = value
            }
        }
        if let identifiers = coverage.onlyTestIdentifiers { payload["only_test_identifiers"] = identifiers }
        if let result = coverage.result {
            if let block = await coverageBlock(result, coverage: coverage, testRunID: payload["id"] as? String ?? "") {
                payload["coverage"] = block
            }
            if let evidence = result.evidence { payload["coverage_evidence"] = evidence }
        }
        await submit(payload, kind: "tests")
        await GitHistoryService().upload(
            history, workingDirectory: directory, fullHandle: handle, serverURL: serverURL, coverage: true
        )
    }

    private func coverageBlock(_ result: CargoCoverage.Result, coverage: CargoCoverage.Report, testRunID: String) async
        -> [String: Any]?
    {
        var block: [String: Any] = [
            "tool": "llvm-cov", "tool_version": coverage.toolVersion, "platform": coverage.platform, "partial": result.partial,
        ]
        var files = result.files
        let paths = files.compactMap { $0["path"] as? String }
        let blobs = await CargoCoverage.blobIDs(
            paths: paths, root: coverage.repositoryRoot, process: process, environment: environment
        )
        for index in files.indices {
            if let path = files[index]["path"] as? String, let blob = blobs[path] { files[index]["git_blob_id"] = blob }
        }
        let lines = files.compactMap { try? JSONSerialization.data(withJSONObject: $0) }
        let compressed = CargoCoverage.deflate(Data(lines.joined(separator: Data("\n".utf8))))
        let threshold = (try? await GetCoverageSettingsService().inlineThresholdBytes(fullHandle: handle, serverURL: serverURL))
            ?? 5_000_000
        guard compressed.count > threshold else {
            block["files"] = files
            return block
        }
        do {
            let upload = try await CreateCoverageUploadService().createCoverageUpload(
                fullHandle: handle, serverURL: serverURL, testRunId: testRunID
            )
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("tuist-coverage-\(UUID().uuidString).deflate")
            defer { try? FileManager.default.removeItem(at: file) }
            try compressed.write(to: file)
            try await CoverageFileUploader().upload(file: AbsolutePath(validating: file.path), to: upload.uploadURL)
            block["storage_key"] = upload.storageKey
            return block
        } catch {
            AlertController.current
                .warning(.alert("The run's code coverage could not be uploaded: \(error.localizedDescription)"))
            return nil
        }
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
