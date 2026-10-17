import FileSystem
import Foundation
import Path
import TuistREAPI
#if os(Linux)
    import TuistCoreCache
#else
    import TuistCore
#endif

struct CargoCompilationCache {
    let invocation: CargoCacheInvocation
    let root: URL
    var remote: (any REAPICacheStoring)?
    let measurement: CargoCacheMeasurement

    private let fileSystem: any FileSysteming
    private let command: Data
    private let action: Data
    private let actionDigest: REAPI.Digest

    init(
        invocation: CargoCacheInvocation, root: URL, remote: (any REAPICacheStoring)?, measurement: CargoCacheMeasurement,
        fileSystem: any FileSysteming = FileSystem()
    ) throws {
        self.invocation = invocation
        self.root = root
        self.remote = remote
        self.measurement = measurement
        self.fileSystem = fileSystem
        command = try REAPI.Command.with {
            $0.arguments = ["tuist-swift-cargo-cache-v1", invocation.key.hash, String(invocation.key.sizeBytes)]
        }.serializedData()
        let commandDigest = REAPI.digest(command)
        action = try REAPI.Action.with {
            $0.commandDigest = commandDigest
            $0.inputRootDigest = REAPI.emptyBlob
        }.serializedData()
        actionDigest = REAPI.digest(action)
    }

    private var index: URL { root.appendingPathComponent("actions/" + actionDigest.hash) }

    func restore() async throws -> Bool {
        if try await restoreLocally() { return true }
        return try await restoreRemotely()
    }

    func restoreLocally() async throws -> Bool {
        try Task.checkCancellation()
        let localStarted = Date()
        let data = try? boundedData(index, maximum: 2_000_000)
        measurement.timing("read", duration: Date().timeIntervalSince(localStarted))
        if let data, let result = try? REAPI.ActionResult(serializedBytes: data),
           (try? await materialize(result, downloadMissing: false)) == true { return true }
        try Task.checkCancellation()
        return false
    }

    func restoreRemotely() async throws -> Bool {
        try Task.checkCancellation()
        guard let remote else { return false }
        do {
            let started = Date()
            let result = try await remote.actionResult(for: actionDigest)
            measurement.timing("read", duration: Date().timeIntervalSince(started))
            guard let result else { return false }
            return try await materialize(result, downloadMissing: true)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            debug(error)
            measurement.failure()
            return false
        }
    }

    func store(stdout: Data, stderr: Data) async throws {
        try Task.checkCancellation()
        guard stdout.count + stderr.count <= 1_000_000 else { return }
        try invocation.validateDependencies()
        guard try invocation.fingerprint() == invocation.key else { return }
        var result = REAPI.ActionResult()
        result.stdoutRaw = stdout
        result.stderrRaw = stderr
        var blobs: [REAPI.Digest: URL] = [:]
        var budget: Int64 = 250_000_000
        for name in try invocation.outputFiles() {
            let file = invocation.output.appendingPathComponent(name)
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let size = properties.fileSize, size <= 100_000_000, size <= budget else { return }
            budget -= Int64(size)
            let digest = try REAPI.digest(file: file)
            let blob = try publish(file, digest: digest)
            blobs[digest] = blob
            result.outputFiles.append(.with { $0.path = name; $0.digest = digest })
            measurement.reference(digest)
        }
        guard try invocation.fingerprint() == invocation.key else { return }
        try Task.checkCancellation()
        let localStarted = Date()
        try write(try result.serializedData(), to: index)
        measurement.timing("write", duration: Date().timeIntervalSince(localStarted))
        guard let remote, invocation.environment["TUIST_CARGO_CACHE_UPLOAD"] == "1" else { return }
        let started = Date()
        do {
            for data in [command, action, Data()] {
                let digest = REAPI.digest(data)
                let file = blobPath(digest)
                try write(data, to: file)
                blobs[digest] = file
            }
            let upload = try await remote.uploadAvailableBlobs(blobs)
            let elapsed = Date().timeIntervalSince(started)
            for digest in blobs.keys {
                let status: String
                if !upload.available.contains(digest) {
                    status = "failed"
                } else if let uploaded = upload.uploaded {
                    status = uploaded.contains(digest) ? "uploaded" : "present"
                } else {
                    continue
                }
                measurement.transfer(digest, operation: "upload", status: status, duration: elapsed)
            }
            guard upload.available == Set(blobs.keys) else {
                if let reason = upload.failures.values.sorted().first { debug(REAPICacheError.uploadFailed(reason: reason)) }
                measurement.failure(upload: true)
                return
            }
            let publicationStarted = Date()
            try await remote.storeActionResult(result, for: actionDigest)
            measurement.timing("write", duration: Date().timeIntervalSince(publicationStarted))
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            debug(error)
            measurement.failure(upload: true)
        }
    }

    private func debug(_ error: any Error) {
        if invocation.environment["TUIST_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("Tuist Cargo cache: \(REAPI.describe(error))\n".utf8))
        }
    }

    private func materialize(_ result: REAPI.ActionResult, downloadMissing: Bool) async throws -> Bool {
        guard result.exitCode == 0, result.outputDirectories.isEmpty,
              result.outputFileSymlinks.isEmpty, result.outputDirectorySymlinks.isEmpty, result.outputSymlinks.isEmpty,
              !result.hasStdoutDigest, !result.hasStderrDigest,
              result.stdoutRaw.count + result.stderrRaw.count <= 1_000_000,
              result.outputFiles.count <= 128,
              Set(result.outputFiles.map(\.path)).count == result.outputFiles.count,
              Set(invocation.files).isSubset(of: Set(result.outputFiles.map(\.path))),
              result.outputFiles.allSatisfy({ invocation.acceptsOutput($0.path) })
        else { return false }
        var missing: [REAPI.Digest: URL] = [:]
        var budget: Int64 = 250_000_000
        let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for file in result.outputFiles {
            try REAPI.validate(file.digest)
            guard !file.isExecutable, file.digest.sizeBytes <= 100_000_000, file.digest.sizeBytes <= budget else { return false }
            budget -= file.digest.sizeBytes
            if await !containsBlob(file.digest) { missing[file.digest] = staging.appendingPathComponent(file.digest.hash) }
        }
        if !missing.isEmpty {
            guard downloadMissing, let remote else { return false }
            let started = Date()
            let downloaded = try await remote.downloadAvailableBlobs(missing)
            let elapsed = Date().timeIntervalSince(started)
            var complete = true
            for (digest, file) in missing {
                let verified = downloaded.contains(digest) && (try? REAPI.digest(file: file)) == digest
                measurement.transfer(digest, operation: "download", status: verified ? "downloaded" : "failed", duration: elapsed)
                if verified { _ = try publish(file, digest: digest) } else { complete = false }
            }
            guard complete else { measurement.failure(); return false }
        }
        guard try invocation.fingerprint() == invocation.key else { return false }
        let properties = try invocation.output.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard properties.isDirectory == true, properties.isSymbolicLink != true else { return false }
        for file in result.outputFiles {
            let destination = invocation.output.appendingPathComponent(file.path)
            if FileManager.default.fileExists(atPath: destination.path) {
                let properties = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard properties.isRegularFile == true, properties.isSymbolicLink != true else { return false }
            }
            let temporary = staging.appendingPathComponent(file.path)
            try FileManager.default.copyItem(at: blobPath(file.digest), to: temporary)
            let properties = try temporary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  try REAPI.digest(file: temporary) == file.digest else { return false }
        }
        try Task.checkCancellation()
        guard try invocation.fingerprint() == invocation.key else { return false }
        for file in result.outputFiles {
            let destination = invocation.output.appendingPathComponent(file.path)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: staging.appendingPathComponent(file.path), to: destination)
            measurement.reference(file.digest)
        }
        try write(try result.serializedData(), to: index)
        FileHandle.standardOutput.write(result.stdoutRaw)
        FileHandle.standardError.write(result.stderrRaw)
        return true
    }

    private func blobPath(_ digest: REAPI.Digest) -> URL { root.appendingPathComponent("blobs/" + digest.hash) }

    private func containsBlob(_ digest: REAPI.Digest) async -> Bool {
        let file = blobPath(digest)
        guard let path = try? AbsolutePath(validating: file.path),
              let properties = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              properties.isRegularFile == true, properties.isSymbolicLink != true,
              properties.fileSize == Int(exactly: digest.sizeBytes),
              (try? REAPI.digest(file: file)) == digest else { return false }
        await fileSystem.markCacheEntryUsed(at: path)
        return true
    }

    private func publish(_ file: URL, digest: REAPI.Digest) throws -> URL {
        let destination = blobPath(digest)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: file, to: temporary)
        guard try REAPI.digest(file: temporary) == digest else { throw REAPICacheError.corruptBlob }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    private func boundedData(_ file: URL, maximum: Int) throws -> Data {
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              let size = properties.fileSize, size <= maximum else { throw REAPICacheError.corruptBlob }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count == properties.fileSize, data.count <= maximum else { throw REAPICacheError.corruptBlob }
        return data
    }
}
