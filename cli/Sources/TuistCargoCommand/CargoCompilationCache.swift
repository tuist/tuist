import Foundation
import TuistREAPI

protocol CargoCacheAction {
    var cacheVersion: String { get }
    var arguments: [String] { get }
    var key: REAPI.Digest { get }
    var environment: [String: String] { get }
    var output: URL { get }
    var name: String { get }
    var kind: String { get }
    var files: [String] { get }
    func fingerprint() throws -> REAPI.Digest
    func validateDependencies(restoring: Bool) async throws
    func certifyOutputs(metadataOnly: Bool) throws
    /// Certifies outputs whose dependencies and key the caller has just checked, without checking them again.
    func certifyCheckedOutputs() throws
    func outputFiles() throws -> [String]
    func acceptsOutput(_ file: String) -> Bool
    /// Extra compiler arguments the cached compilation runs with.
    var remapArguments: [String] { get }
    /// Dep-info and compiler messages, as stored (machine-specific roots replaced) and as restored.
    func storedOutput(_ data: Data) -> Data?
    func restoredOutput(_ data: Data) -> Data?
    /// Machine roots an output names that its key does not; such an entry would behave differently elsewhere.
    func unkeyedRoots(in data: Data) -> [String]
    /// The one output stored and restored with its executable bit, a linked binary.
    var executableOutput: String? { get }
}

extension CargoCacheAction {
    func certifyCheckedOutputs() throws { try certifyOutputs(metadataOnly: false) }
    var executableOutput: String? { nil }
    var remapArguments: [String] { [] }
    func storedOutput(_ data: Data) -> Data? { data }
    func restoredOutput(_ data: Data) -> Data? { data }
    func unkeyedRoots(in _: Data) -> [String] { [] }
}

struct CargoCompilationCache {
    let invocation: any CargoCacheAction
    let root: URL
    var remote: (any REAPICacheStoring)?
    let measurement: CargoCacheMeasurement
    /// Where a hit's compiler messages go: this process's streams for a hook, or the hook client a session serves.
    var replay: (_ stdout: Data, _ stderr: Data) -> Void = { stdout, stderr in
        FileHandle.standardOutput.write(stdout)
        FileHandle.standardError.write(stderr)
    }

    private let command: Data
    private let action: Data
    private let actionDigest: REAPI.Digest

    init(
        invocation: any CargoCacheAction, root: URL, remote: (any REAPICacheStoring)?, measurement: CargoCacheMeasurement
    ) throws {
        self.invocation = invocation
        self.root = root
        self.remote = remote
        self.measurement = measurement
        command = try REAPI.Command.with {
            $0.arguments = [invocation.cacheVersion, invocation.key.hash, String(invocation.key.sizeBytes)]
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
        let result: REAPI.ActionResult?
        do {
            let started = Date()
            result = try await remote.actionResult(for: actionDigest)
            measurement.timing("read", duration: Date().timeIntervalSince(started))
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            debug(error)
            if !CargoRemoteCache.isOverloaded(error) { measurement.failure() }
            return false
        }
        guard let result else { return false }
        do {
            return try await materialize(result, downloadMissing: true)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            debug(error)
            return false
        }
    }

    /// Publishes the compilation's outputs. `keyedAfterCompiling` says the key was computed from inputs read once the
    /// compiler had finished, so only the check after copying the outputs is needed; a key taken before it ran is
    /// checked first, since a source may have changed while it compiled.
    func store(stdout: Data, stderr: Data, keyedAfterCompiling: Bool = false) async throws {
        guard try await admit(keyedAfterCompiling: keyedAfterCompiling) else { return }
        try await publish(stdout: stdout, stderr: stderr)
    }

    /// Checks the inputs the key names and certifies the outputs for strict dependents, which Cargo may start as soon
    /// as the compiler's exit is reported. `false` when the compilation must not be published.
    func admit(keyedAfterCompiling: Bool = false) async throws -> Bool {
        try Task.checkCancellation()
        try await invocation.validateDependencies(restoring: false)
        guard try keyedAfterCompiling || invocation.fingerprint() == invocation.key else { return false }
        try? invocation.certifyCheckedOutputs()
        return true
    }

    /// Stores an admitted compilation's outputs, which must still match the key once copied.
    func publish(stdout: Data, stderr: Data) async throws {
        guard stdout.isEmpty, stderr.count <= 1_000_000, let messages = Self.messages(stderr) else {
            return refuse("its output is not only rustc's messages")
        }
        // Rendered diagnostics depend on the terminal width, which keys leave out: record it beside them.
        let widthMarker = messages.diagnostics ? Self.widthMarker(invocation.arguments) : Data()
        guard let storedStderr = invocation.storedOutput(widthMarker + stderr) else {
            return refuse("its messages name a path outside the known roots")
        }
        var result = REAPI.ActionResult()
        result.stdoutRaw = stdout
        result.stderrRaw = storedStderr
        let relocated = root.appendingPathComponent("staging/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: relocated) }
        var blobs: [REAPI.Digest: URL] = [:]
        var budget = Self.maximumBytes
        for name in try invocation.outputFiles() {
            let file = invocation.output.appendingPathComponent(name)
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let size = properties.fileSize, size <= budget
            else { return refuse("\(name) is not a regular file within the size budget") }
            budget -= Int64(size)
            var content = file
            if !name.hasSuffix(".d") {
                let unkeyed = invocation.unkeyedRoots(in: try Data(contentsOf: file))
                guard unkeyed.isEmpty else {
                    let roots = unkeyed.joined(separator: ", ")
                    return refuse("\(name) names \(roots), which its key does not")
                }
            }
            if name.hasSuffix(".d") {
                guard let stored = invocation.storedOutput(try Data(contentsOf: file)) else {
                    return refuse("\(name) names a path outside the known roots")
                }
                try FileManager.default.createDirectory(at: relocated, withIntermediateDirectories: true)
                content = relocated.appendingPathComponent(name)
                try stored.write(to: content)
            }
            let digest = try blobStore.publish(content)
            blobs[digest] = blobStore.path(digest)
            result.outputFiles.append(.with {
                $0.path = name; $0.digest = digest; $0.isExecutable = name == invocation.executableOutput
            })
            measurement.reference(digest)
        }
        guard try invocation.fingerprint() == invocation.key else { return refuse("an input changed while it was stored") }
        try Task.checkCancellation()
        let localStarted = Date()
        try CargoBlobStore.write(try result.serializedData(), to: index)
        measurement.timing("write", duration: Date().timeIntervalSince(localStarted))
        CargoCacheJournal.use("actions/" + actionDigest.hash, environment: invocation.environment)
        guard let remote else { return }
        if let marker = CargoCacheSetup.readOnlyMarker(environment: invocation.environment),
           FileManager.default.fileExists(atPath: marker.path) { return }
        let started = Date()
        do {
            for data in [command, action, Data()] {
                let digest = REAPI.digest(data)
                let file = blobStore.path(digest)
                try CargoBlobStore.write(data, to: file)
                blobs[digest] = file
            }
            // Inside a session the outer command uploads once Cargo exits, so no compilation waits on the network.
            if CargoCacheJournal.defersPublication(invocation.environment),
               CargoCacheJournal.deferPublication(result, for: actionDigest, blobs: blobs, environment: invocation.environment)
            { return }
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

    /// Whether a stream holds only rustc's JSON messages (artifact notifications, diagnostics, future-incompatibility
    /// reports, unused-extern reports, and this cache's width marker), and whether any are diagnostics; `nil` for
    /// anything else. Cargo 1.100 asks for unused-extern reports (`--json=unused-externs-silent`) for its
    /// `unused_dependencies` lint; a hit replays them like diagnostics, so the lint still sees cached crates.
    static func messages(_ data: Data) -> (diagnostics: Bool, width: String?)? {
        var diagnostics = false
        var width: String?
        for line in data.split(separator: 10) {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = message["$message_type"] as? String else { return nil }
            switch type {
            case "artifact", "future_incompat", "unused_extern": continue
            case "diagnostic": diagnostics = true
            case widthMessage:
                guard width == nil, let value = message["width"] as? String else { return nil }
                width = value
            default: return nil
            }
        }
        return (diagnostics, width)
    }

    static let widthMessage = "tuist-diagnostic-width"
    /// Matches the unit cache: debug rlibs of large crates (aws-sdk-s3, mise) pass 100 MB, and blobs stream over ByteStream.
    static let maximumBytes: Int64 = 4_000_000_000

    static func diagnosticWidth(_ arguments: [String]) -> String {
        var width = ""
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--diagnostic-width=") { width = String(argument.dropFirst(19)) }
            if argument == "--diagnostic-width", index + 1 < arguments.count { width = arguments[index + 1] }
        }
        return width
    }

    static func widthMarker(_ arguments: [String]) -> Data {
        let line = try? JSONSerialization.data(withJSONObject: [
            "$message_type": widthMessage,
            "width": diagnosticWidth(arguments),
        ])
        return (line ?? Data()) + Data([10])
    }

    private func refuse(_ reason: String) {
        if invocation.environment["TUIST_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("Tuist Cargo cache: \(invocation.name) was not stored: \(reason)\n".utf8))
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
              result.stdoutRaw.isEmpty, result.stderrRaw.count <= 1_000_000, let messages = Self.messages(result.stderrRaw),
              // Diagnostics replay only at the width they were rendered at.
              !messages.diagnostics || messages.width == Self.diagnosticWidth(invocation.arguments),
              result.outputFiles.count <= 128,
              Set(result.outputFiles.map(\.path)).count == result.outputFiles.count,
              Set(invocation.files).isSubset(of: Set(result.outputFiles.map(\.path))),
              result.outputFiles.allSatisfy({ invocation.acceptsOutput($0.path) })
        else { return false }
        var missing: [REAPI.Digest: URL] = [:]
        var budget = Self.maximumBytes
        let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for file in result.outputFiles {
            try REAPI.validate(file.digest)
            guard file.isExecutable == (file.path == invocation.executableOutput),
                  file.digest.sizeBytes <= budget else { return false }
            budget -= file.digest.sizeBytes
            // Not hashed here: materialization verifies each blob before cloning it.
            if blobStore.contains(file.digest) {
                blobStore.markUsed(file.digest)
            } else {
                missing[file.digest] = staging.appendingPathComponent(file.digest.hash)
            }
        }
        if !missing.isEmpty {
            guard downloadMissing, let remote else { return false }
            let started = Date()
            let download: REAPIBlobDownload
            do {
                download = try await remote.downloadBlobs(missing)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                if !CargoRemoteCache.isOverloaded(error) { measurement.failure() }
                throw error
            }
            let elapsed = Date().timeIntervalSince(started)
            var complete = true
            for (digest, file) in missing {
                let verified = download.available.contains(digest) && (try? blobStore.publish(file, expecting: digest)) != nil
                measurement.transfer(digest, operation: "download", status: verified ? "downloaded" : "failed", duration: elapsed)
                if !verified { complete = false }
            }
            guard complete else { measurement.failure(endpoint: !download.remoteFailures.isEmpty); return false }
        }
        try await invocation.validateDependencies(restoring: true)
        let replayed = result.stderrRaw.split(separator: 10, omittingEmptySubsequences: false).filter { line in
            (try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])?["$message_type"] as? String != Self
                .widthMessage
        }
        // The fingerprint is rechecked once the outputs are staged, right before they move into place: the lookup
        // just computed it, and a change before staging is caught there too.
        guard let restoredStderr = invocation.restoredOutput(Data(replayed.joined(separator: [10]))) else { return false }
        let properties = try invocation.output.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard properties.isDirectory == true, properties.isSymbolicLink != true else { return false }
        // Blobs are verified through the persistent identity memo, as dependency units are, rather than by hashing
        // each copy: an unchanged blob keeps its identity, any write to it changes it, and a clone shares its content.
        let verifier = CargoInputHasher(sessionDirectory: root.appendingPathComponent("verified"))
        for file in result.outputFiles {
            let destination = invocation.output.appendingPathComponent(file.path)
            if FileManager.default.fileExists(atPath: destination.path) {
                let properties = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard properties.isRegularFile == true, properties.isSymbolicLink != true else { return false }
            }
            let blob = blobStore.path(file.digest)
            guard try verifier.digest(blob, shared: true) == file.digest else { return false }
            let temporary = staging.appendingPathComponent(file.path)
            try FileManager.default.copyItem(at: blob, to: temporary)
            let properties = try temporary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  properties.fileSize.map(Int64.init) == file.digest.sizeBytes else { return false }
            if file.path.hasSuffix(".d") {
                guard let restored = invocation.restoredOutput(try Data(contentsOf: temporary)) else { return false }
                try restored.write(to: temporary)
            }
            if file
                .isExecutable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path) }
        }
        try Task.checkCancellation()
        guard try invocation.fingerprint() == invocation.key else { return false }
        // Dependents key these outputs next. Cargo runs nothing else that writes this crate's outputs while its
        // compilation (this hook) runs, so the session records their digests instead of hashing them again.
        let session = invocation.environment["TUIST_CARGO_SESSION"]
            .map { CargoInputHasher(sessionDirectory: URL(fileURLWithPath: $0)) }
        for file in result.outputFiles {
            let destination = invocation.output.appendingPathComponent(file.path)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: staging.appendingPathComponent(file.path), to: destination)
            measurement.reference(file.digest)
            if !file.path.hasSuffix(".d") {
                session?.remember(destination, digest: file.digest) { $0.fields[2] == String(file.digest.sizeBytes) }
            }
        }
        try invocation.certifyOutputs(metadataOnly: false)
        // A remote entry is kept locally; a local one, read from the index just now, renews its use like a blob.
        if downloadMissing {
            try CargoBlobStore.write(try result.serializedData(), to: index)
        } else {
            CargoBlobStore.markUsed(index.path)
        }
        CargoCacheJournal.use("actions/" + actionDigest.hash, environment: invocation.environment)
        replay(result.stdoutRaw, restoredStderr)
        return true
    }

    private var blobStore: CargoBlobStore { CargoBlobStore(root: root) }

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
