import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Path
import TuistCI
import TuistHTTP
import TuistProcess
import TuistServer

struct CargoShardService {
    struct Shard {
        let id: String
        let modules: [String]
        let archive: URL
    }

    let runner: CommandRunning

    func plan(
        arguments: [String],
        executable: String,
        directory: AbsolutePath,
        environment: [String: String],
        fullHandle: String,
        serverURL: URL
    ) async throws {
        guard let reference = environment["TUIST_SHARD_REFERENCE"] ?? CIController().ciInfo()?.shardReference else {
            throw CargoReportError(message: "Set TUIST_SHARD_REFERENCE to identify the shard plan.")
        }
        let parsed = try Self.planningArguments(arguments)
        let archive = URL(fileURLWithPath: environment["TUIST_TEST_SHARD_ARCHIVE_PATH"] ?? directory.appending(
            components: ".tuist",
            "cargo-tests.tar.zst"
        ).pathString)
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = CargoProcess(runner: runner)
        try await process.execute(
            executable,
            arguments: CargoInvocation.inserting(["--archive-file", archive.path], into: parsed.arguments),
            environment: environment,
            directory: directory
        )
        let listing = try await process.capture(
            executable,
            arguments: ["nextest", "list", "--archive-file", archive.path, "--message-format", "json"],
            environment: environment,
            directory: directory
        )
        let inventory = try JSONDecoder().decode(NextestInventory.self, from: Data(listing.utf8))
        guard !inventory.modules.isEmpty else { throw CargoReportError(message: "No enabled nextest test binaries were found.") }
        let options = parsed.options
        let plan = try await CreateShardPlanService(concurrentModules: inventory.modules).createShardPlan(
            fullHandle: fullHandle, serverURL: serverURL, reference: reference, modules: inventory.modules,
            parallelizableModules: nil, testSuites: nil, skippedTestSuites: nil,
            shardMin: options["--shard-min"], shardMax: options["--shard-max"], shardTotal: options["--shard-total"],
            shardMaxDuration: options["--shard-max-duration"], shardGranularity: .module, buildRunId: nil, gitBranch: nil
        )
        if environment["TUIST_TEST_SHARD_ARCHIVE_PATH"] == nil {
            try await upload(archive, planID: plan.id, reference: reference, fullHandle: fullHandle, serverURL: serverURL)
        }
        try Self.emit(plan, environment: environment)
    }

    static func planningArguments(_ arguments: [String]) throws -> (arguments: [String], options: [String: Int]) {
        var forwarded = arguments
        guard let command = CargoInvocation(arguments).commandIndex
        else { throw CargoReportError(message: "Missing test-build command.") }
        forwarded.replaceSubrange(command ... command, with: ["nextest", "archive"])
        var options: [String: Int] = [:]
        var index = 0
        let names: Set<String> = ["--shard-min", "--shard-max", "--shard-total", "--shard-max-duration"]
        while index < forwarded.count {
            if forwarded[index] == "--" { break }
            let parts = forwarded[index].split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first, names.contains(key) else { index += 1; continue }
            let inline = parts.count == 2
            guard inline || index + 1 < forwarded.count, let value = Int(inline ? parts[1] : forwarded[index + 1]),
                  value > 0
            else {
                throw CargoReportError(message: "\(key) must be a positive integer.")
            }
            guard options[key] == nil else { throw CargoReportError(message: "\(key) must be specified only once.") }
            options[key] = value
            forwarded.removeSubrange(index ... (inline ? index : index + 1))
        }
        return (forwarded, options)
    }

    private func upload(_ archive: URL, planID: String, reference: String, fullHandle: String, serverURL: URL) async throws {
        let uploadID = try await StartShardUploadService().startUpload(
            fullHandle: fullHandle,
            serverURL: serverURL,
            shardPlanId: planID,
            reference: reference,
            artifact: nil
        )
        let parts = try await MultipartUploadArtifactService().multipartUploadArtifact(
            artifactPath: AbsolutePath(validating: archive.path),
            generateUploadURL: { part in
                try await MultipartUploadGenerateURLShardsService().generateUploadURL(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    shardPlanId: planID,
                    reference: reference,
                    uploadId: uploadID,
                    partNumber: part.number,
                    artifact: nil
                )
            }, updateProgress: { _ in }
        )
        try await MultipartUploadCompleteShardsService().completeUpload(
            fullHandle: fullHandle,
            serverURL: serverURL,
            shardPlanId: planID,
            reference: reference,
            uploadId: uploadID,
            parts: parts.map { (partNumber: $0.partNumber, etag: $0.etag) },
            artifact: nil
        )
    }

    private static func emit(_ plan: Components.Schemas.ShardPlan, environment: [String: String]) throws {
        let shards = Array(0 ..< plan.shard_count)
        let data = try JSONSerialization.data(
            withJSONObject: ["shard_plan_id": plan.id, "shards": shards],
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        if let output = environment["GITHUB_OUTPUT"], let matrix = String(
            data: try JSONEncoder().encode(shards),
            encoding: .utf8
        ) {
            let file = try FileHandle(forWritingTo: URL(fileURLWithPath: output))
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: Data("shard-plan-id=\(plan.id)\nshards=\(matrix)\n".utf8))
        }
    }

    func prepare(
        index: Int,
        directory: AbsolutePath,
        temporary: URL,
        fullHandle: String,
        serverURL: URL,
        environment: [String: String]
    ) async throws -> Shard {
        let planID = environment["TUIST_SHARD_PLAN_ID"]
        guard let reference = environment["TUIST_SHARD_REFERENCE"] ?? CIController().ciInfo()?.shardReference ?? planID else {
            throw CargoReportError(message: "Set TUIST_SHARD_REFERENCE or TUIST_SHARD_PLAN_ID for shard execution.")
        }
        let shard = try await GetShardService().getShard(
            fullHandle: fullHandle,
            serverURL: serverURL,
            reference: reference,
            shardPlanId: planID,
            shardIndex: index
        )
        guard shard.suites.additionalProperties.isEmpty, (shard.skip ?? []).isEmpty else {
            throw CargoReportError(message: "Rust execution requires a module-granularity shard plan.")
        }
        if let local = environment["TUIST_TEST_SHARD_ARCHIVE_PATH"] {
            let archive = URL(fileURLWithPath: local, relativeTo: URL(fileURLWithPath: directory.pathString)).standardizedFileURL
            guard FileManager.default.fileExists(atPath: archive.path)
            else { throw CargoReportError(message: "The local nextest shard archive is missing.") }
            return Shard(id: shard.shard_plan_id, modules: shard.modules, archive: archive)
        }
        guard shard.download_urls.count == 1, let url = URL(string: shard.download_urls[0]),
              ["https", "http"].contains(url.scheme ?? "")
        else {
            throw CargoReportError(message: "The nextest shard archive is not available.")
        }
        let archive = temporary.appendingPathComponent("tests.tar.zst")
        try await Self.downloadArchive(from: url, to: archive)
        return Shard(id: shard.shard_plan_id, modules: shard.modules, archive: archive)
    }

    static func downloadArchive(
        from url: URL,
        to archive: URL,
        transfer: RetryingURLTransfer = RetryingURLTransfer(urlSession: .tuistDefault)
    ) async throws {
        let (file, response) = try await transfer.download(URLRequest(url: url))
        guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: file)
            throw CargoReportError(message: "Downloading the nextest shard archive failed.")
        }
        try FileManager.default.moveItem(at: file, to: archive)
    }
}
