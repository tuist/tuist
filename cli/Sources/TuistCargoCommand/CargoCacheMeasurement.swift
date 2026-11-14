import Foundation
import TuistREAPI

final class CargoCacheMeasurement {
    let invocation: any CargoCacheAction
    private var counters = Dictionary(uniqueKeysWithValues: CargoCacheReport.counters.map { ($0, UInt64(0)) })
    private var records: [[String: Any]] = []
    private(set) var hasRemoteFailure = false

    init(invocation: any CargoCacheAction) {
        self.invocation = invocation
    }

    func outcome(hit: Bool) {
        counters[hit ? "hits" : "misses"] = 1
        records.append([
            "record": "task", "key": Self.key(invocation.key), "name": invocation.name,
            "kind": invocation.kind, "status": hit ? "hit" : "miss",
        ])
    }

    func timing(_ operation: String, duration: TimeInterval) {
        records.append([
            "record": "timing", "key": Self.key(invocation.key), "operation": operation,
            "duration_ns": Self.nanoseconds(duration),
        ])
    }

    func transfer(_ digest: REAPI.Digest, operation: String, status: String, duration: TimeInterval) {
        guard digest != REAPI.emptyBlob else { return }
        if status == "downloaded" || status == "uploaded" {
            let counter = status == "downloaded" ? "downloaded_bytes" : "uploaded_bytes"
            counters[counter, default: 0] += UInt64(max(0, digest.sizeBytes))
        }
        records.append([
            "record": "cas", "key": Self.key(digest), "operation": operation, "status": status,
            "size_bytes": UInt64(max(0, digest.sizeBytes)), "duration_ns": Self.nanoseconds(duration),
        ])
    }

    func reference(_ digest: REAPI.Digest) {
        records.append(["record": "reference", "key": Self.key(invocation.key), "object": Self.key(digest)])
    }

    func failure(upload: Bool = false, endpoint: Bool = true) {
        counters[upload ? "background_upload_failures" : "remote_failures", default: 0] += 1
        if !upload, endpoint { hasRemoteFailure = true }
    }

    func write() {
        Self.write(counters: counters, records: records, environment: invocation.environment)
    }

    /// Records a crate compilation the cache could not take, such as a test harness: it compiled without consulting
    /// the cache, so the summary's task misses and hit rate cover every crate that compiled, not only cacheable ones.
    static func uncached(_ arguments: [String], environment: [String: String]) {
        guard environment["TUIST_CARGO_CACHE_DIR"] != nil,
              let name = CargoCacheInputs.values("--crate-name", in: arguments).first, !name.isEmpty,
              !arguments.contains(where: { $0.hasPrefix("--print") }),
              arguments.dropFirst().contains(where: { $0.hasSuffix(".rs") }),
              let encoded = try? JSONSerialization.data(withJSONObject: Array(arguments.dropFirst()))
        else { return }
        var counters = Dictionary(uniqueKeysWithValues: CargoCacheReport.counters.map { ($0, UInt64(0)) })
        counters["unconsulted"] = 1
        let record: [String: Any] = [
            "record": "task", "key": key(REAPI.digest(encoded)), "name": name, "kind": "rust", "status": "unconsulted",
        ]
        write(counters: counters, records: [record], environment: environment)
    }

    private static func write(counters: [String: UInt64], records: [[String: Any]], environment: [String: String]) {
        guard let session = environment["TUIST_CARGO_SESSION"] else { return }
        let root = URL(fileURLWithPath: session)
        let id = UUID().uuidString
        let statistics = root.appendingPathComponent("cache-reports")
        let details = root.appendingPathComponent("cache-details")
        do {
            var payload: [String: Any] = counters.mapValues { $0 as Any }
            payload["version"] = 1
            try CargoBlobStore.write(
                JSONSerialization.data(withJSONObject: payload), to: statistics.appendingPathComponent(id + ".json")
            )
            var data = Data()
            for record in records.prefix(500) {
                data.append(try JSONSerialization.data(withJSONObject: record))
                data.append(UInt8(10))
            }
            try CargoBlobStore.write(data, to: details.appendingPathComponent(id + ".ndjson"))
        } catch {}
    }

    private static func key(_ digest: REAPI.Digest) -> String {
        "sha256:\(digest.hash):\(digest.sizeBytes)"
    }

    private static func nanoseconds(_ duration: TimeInterval) -> UInt64 {
        UInt64(max(0, min(duration * 1_000_000_000, 9_000_000_000_000_000)))
    }
}
