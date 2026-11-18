import Foundation
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// What compiler hooks tell the outer Cargo command through its session directory, after blaze: no build waits for
/// the network. Hooks note every cache entry they use, which becomes the project's prefetch list, and inside a session
/// with a remote they leave publications to the outer command, which uploads them in one batch once Cargo exits.
enum CargoCacheJournal {
    /// Set by the outer command when it publishes for its hooks.
    static let writeBehindVariable = "TUIST_CARGO_WRITE_BEHIND"

    /// An action result and the blobs it needs remotely, written by a hook for the outer command to publish.
    struct Publication: Codable {
        struct Blob: Codable {
            var hash: String
            var size: Int64
            var path: String

            var digest: REAPI.Digest {
                .with { [hash, size] in $0.hash = hash; $0.sizeBytes = size }
            }
        }

        var action: String
        var actionSize: Int64
        var result: Data
        var blobs: [Blob]
    }

    static func defersPublication(_ environment: [String: String]) -> Bool {
        environment[writeBehindVariable] == "1" && environment["TUIST_CARGO_SESSION"] != nil
    }

    /// Leaves a publication to the outer command. `false` when it cannot be recorded; the caller then uploads itself.
    static func deferPublication(
        _ result: REAPI.ActionResult, for action: REAPI.Digest, blobs: [REAPI.Digest: URL], environment: [String: String]
    ) -> Bool {
        guard let session = environment["TUIST_CARGO_SESSION"], let data = try? result.serializedData() else { return false }
        let publication = Publication(
            action: action.hash, actionSize: action.sizeBytes, result: data,
            blobs: blobs.map { .init(hash: $0.key.hash, size: $0.key.sizeBytes, path: $0.value.path) }
        )
        let directory = URL(fileURLWithPath: session).appendingPathComponent("publications")
        guard let encoded = try? JSONEncoder().encode(publication),
              (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              (try? encoded.write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)) != nil
        else { return false }
        return true
    }

    /// Notes a cache-relative index file this build used, so the next build can fetch it before it is needed.
    static func use(_ path: String, environment: [String: String]) {
        guard let session = environment["TUIST_CARGO_SESSION"], isIndexPath(path) else { return }
        let descriptor = open(session + "/cache-used", O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        // One short `O_APPEND` write is atomic, so concurrent hooks never interleave lines.
        let line = Array((path + "\n").utf8)
        _ = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }

    /// The index files hooks noted, most recent last, without repeats.
    static func used(session: URL) -> [String] {
        guard let text = try? String(contentsOf: session.appendingPathComponent("cache-used"), encoding: .utf8) else { return [] }
        var seen: Set<String> = []
        return text.split(separator: "\n").map(String.init).filter { isIndexPath($0) && seen.insert($0).inserted }
    }

    /// Cache index files whose content selects outputs: action results, script runs and remembered source/read lists.
    static func isIndexPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        func isDigest(_ value: Substring) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
        }
        switch parts[0] {
        case "actions", "script-actions": return isDigest(parts[1])
        case "reads": return parts[1].hasSuffix(".json") && isDigest(parts[1].dropLast(5))
        default: return false
        }
    }

    /// Uploads every publication hooks left, in one batch of blobs, then their action results. Never fails the build.
    static func flush(session: URL, remote: any REAPICacheStoring, debug: (String) -> Void) async {
        let directory = session.appendingPathComponent("publications")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
        let publications = names.compactMap { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap { try? JSONDecoder().decode(
                Publication.self,
                from: $0
            ) }
        }
        guard !publications.isEmpty else { return }
        var blobs: [REAPI.Digest: URL] = [:]
        for publication in publications {
            for blob in publication.blobs {
                blobs[blob.digest] = URL(fileURLWithPath: blob.path)
            }
        }
        let available: Set<REAPI.Digest>
        do {
            available = try await remote.uploadAvailableBlobs(blobs).available
        } catch {
            debug("deferred upload failed: \(REAPI.describe(error))")
            return
        }
        let ready = publications.filter { publication in
            publication.blobs.allSatisfy { available.contains($0.digest) }
        }
        let stored = await withTaskGroup(of: Bool.self) { group in
            var stored = 0
            var pending = ready[...]
            func next() -> Bool {
                while let publication = pending.popFirst() {
                    guard let result = try? REAPI.ActionResult(serializedBytes: publication.result) else { continue }
                    let action = REAPI.Digest.with { $0.hash = publication.action; $0.sizeBytes = publication.actionSize }
                    group.addTask { (try? await remote.storeActionResult(result, for: action)) != nil }
                    return true
                }
                return false
            }
            for _ in 0 ..< 16 where next() {}
            while let result = await group.next() {
                if result { stored += 1 }
                _ = next()
            }
            return stored
        }
        debug("published \(stored) of \(publications.count) deferred cache entries")
    }
}
