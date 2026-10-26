import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Path
import TuistCI
import TuistProcess
import TuistServer

struct OnceTestService {
    private struct Artifact: Codable {
        let schema: String
        let shardPlanID: String
        let reportingVersion: Int
        let portablePlan: Data
    }

    let directory: AbsolutePath
    let executable: String
    let fullHandle: String
    let serverURL: URL
    var runner: CommandRunning = CommandRunner()
    var environment: [String: String] = ProcessInfo.processInfo.environment

    func plan(reference: String, target: String?, changedPaths: [String], shardTotal: Int) async throws -> Components.Schemas
        .ShardPlan?
    {
        var arguments = ["query", "test-plan", "--format", "json"]
        if let target { arguments += ["--target", target] }
        arguments += changedPaths.flatMap { ["--changed-path", $0] }
        let (data, error) = try await capture(arguments)
        if let error { throw error }
        let native = try OnceTestPlan.read(data)
        guard !native.plan.batches.isEmpty else { return nil }
        let plan = try await CreateShardPlanService().createShardPlan(
            fullHandle: fullHandle, serverURL: serverURL, reference: reference,
            modules: native.plan.batches.map(\.id), parallelizableModules: nil, testSuites: nil, skippedTestSuites: nil,
            shardMin: nil, shardMax: nil, shardTotal: shardTotal, shardMaxDuration: nil,
            shardGranularity: .module, buildRunId: nil, gitBranch: nil
        )
        guard plan.reporting_version == 1 else {
            throw OnceTestError(
                message: "Once sharding requires immutable shard reporting. Upgrade and enroll the account before planning."
            )
        }
        let temporary = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let artifact = temporary.appendingPathComponent("once-plan.json")
        try JSONEncoder().encode(Artifact(
            schema: "tuist.once_shard_plan.v1", shardPlanID: plan.id, reportingVersion: 1, portablePlan: data
        )).write(to: artifact)
        try await upload(artifact, planID: plan.id, reference: reference)
        return plan
    }

    func run(planID: String, index: Int, attempt: Int, jobs: Int) async throws {
        let shard = try await GetShardService().getShard(
            fullHandle: fullHandle, serverURL: serverURL, reference: planID, shardPlanId: planID, shardIndex: index
        )
        guard shard.shard_plan_id.lowercased() == planID.lowercased(), shard.suites.additionalProperties.isEmpty,
              (shard.skip ?? []).isEmpty, Set(shard.modules).count == shard.modules.count
        else {
            throw OnceTestError(message: "Once requires an exact module-granularity batch assignment.")
        }
        let temporary = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard shard.download_urls.count == 1, let url = URL(string: shard.download_urls[0]),
              ["http", "https"].contains(url.scheme ?? "")
        else {
            throw OnceTestError(message: "The portable Once plan is unavailable. Run the planning job again.")
        }
        let (download, response) = try await RetryingURLTransfer(urlSession: .shared).download(URLRequest(url: url))
        defer { try? FileManager.default.removeItem(at: download) }
        guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode),
              let size = try download.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 96_000_000
        else {
            throw OnceTestError(message: "Downloading the portable Once plan failed or exceeded 96 MB.")
        }
        let artifact = try JSONDecoder().decode(Artifact.self, from: Data(contentsOf: download))
        guard artifact.schema == "tuist.once_shard_plan.v1", artifact.shardPlanID.lowercased() == planID.lowercased(),
              artifact.reportingVersion == 1
        else {
            throw OnceTestError(message: "The downloaded Once artifact belongs to another shard plan.")
        }
        let native = try OnceTestPlan.read(artifact.portablePlan)
        guard Set(shard.modules).isSubset(of: Set(native.plan.batches.map(\.id))) else {
            throw OnceTestError(message: "The shard assignment contains batches absent from the portable Once plan.")
        }
        let file = temporary.appendingPathComponent("plan.json")
        try artifact.portablePlan.write(to: file)
        let started = Date()
        var report = OnceTestReport(modules: [], success: true)
        var processError: CommandError?
        var reportingError: Error?
        if !shard.modules.isEmpty {
            let arguments = [
                "test",
                "--plan",
                file.path,
                "--external-group",
                planID,
                "--partition-index",
                String(index),
                "--jobs",
                String(jobs),
                "--format",
                "json",
            ]
                + shard.modules.flatMap { ["--batch", $0] }
            do {
                let (data, error) = try await capture(arguments)
                processError = error
                report = try OnceTestReport.read(data, plan: native, assigned: shard.modules, processSucceeded: error == nil)
            } catch {
                report = OnceTestReport(modules: [], success: false)
                reportingError = error
            }
        }
        var payload = await metadata()
        payload.merge([
            "id": UUID().uuidString, "build_system": "once", "scheme": "once test",
            "duration": min(Int(Date().timeIntervalSince(started) * 1000), Int(Int32.max)),
            "ran_at": ISO8601DateFormatter().string(from: started),
            "status": report.success ? "success" : "failure", "test_modules": report.modules,
            "shard_plan_id": planID, "shard_index": index, "shard_attempt": attempt, "shard_report_revision": 0,
        ], uniquingKeysWith: { _, new in new })
        do {
            try await OnceTestReportService().submit(
                JSONSerialization.data(withJSONObject: payload), fullHandle: fullHandle, serverURL: serverURL
            )
        } catch {
            if processError == nil { throw error }
            FileHandle.standardError.write(Data("Uploading the Once shard report failed: \(error.localizedDescription)\n".utf8))
        }
        if let processError { throw processError }
        if let reportingError { throw reportingError }
        if !report.success { throw OnceTestError(message: "The assigned Once test batches failed.") }
    }

    private func capture(_ arguments: [String]) async throws -> (Data, CommandError?) {
        var data = Data()
        do {
            for try await event in runner.run(
                arguments: ["/usr/bin/env", executable] + arguments, environment: environment, workingDirectory: directory
            ) {
                switch event {
                case let .standardOutput(bytes):
                    guard data.count + bytes.count <= 64_000_000 else {
                        throw OnceTestError(message: "Once JSON output exceeded 64 MB.")
                    }
                    data.append(contentsOf: bytes)
                case let .standardError(bytes): FileHandle.standardError.write(Data(bytes))
                }
            }
            return (data, nil)
        } catch let error as CommandError {
            return (data, error)
        }
    }

    private func metadata() async -> [String: Any] {
        let ci = CIController().ciInfo()
        var metadata: [String: Any] = ["is_ci": ci != nil]
        metadata["ci_provider"] = ci.map { String(describing: $0.provider) }
        metadata["ci_run_id"] = ci?.runId
        metadata["ci_project_handle"] = ci?.projectHandle
        metadata["ci_host"] = ci?.host
        metadata["git_ref"] = environment["GITHUB_REF"] ?? environment["CI_COMMIT_REF_NAME"]
        for (name, arguments) in [
            ("git_branch", ["rev-parse", "--abbrev-ref", "HEAD"]),
            ("git_commit_sha", ["rev-parse", "HEAD"]),
            ("git_remote_url_origin", ["remote", "get-url", "origin"]),
        ] {
            var output = Data()
            do {
                for try await event in runner.run(
                    arguments: ["/usr/bin/env", "git"] + arguments, environment: environment, workingDirectory: directory
                ) {
                    if case let .standardOutput(bytes) = event,
                       output.count + bytes.count <= 8192 { output.append(contentsOf: bytes) }
                }
                metadata[name] = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch { continue }
        }
        return metadata
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tuist-once-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func upload(_ file: URL, planID: String, reference: String) async throws {
        let uploadID = try await StartShardUploadService().startUpload(
            fullHandle: fullHandle, serverURL: serverURL, shardPlanId: planID, reference: reference, artifact: nil
        )
        let parts = try await MultipartUploadArtifactService().multipartUploadArtifact(
            artifactPath: AbsolutePath(validating: file.path),
            generateUploadURL: { part in
                try await MultipartUploadGenerateURLShardsService().generateUploadURL(
                    fullHandle: fullHandle, serverURL: serverURL, shardPlanId: planID, reference: reference,
                    uploadId: uploadID, partNumber: part.number, artifact: nil
                )
            }, updateProgress: { _ in }
        )
        try await MultipartUploadCompleteShardsService().completeUpload(
            fullHandle: fullHandle, serverURL: serverURL, shardPlanId: planID, reference: reference,
            uploadId: uploadID, parts: parts.map { (partNumber: $0.partNumber, etag: $0.etag) }, artifact: nil
        )
    }
}
