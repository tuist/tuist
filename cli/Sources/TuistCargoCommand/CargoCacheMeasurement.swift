import Foundation
import TuistREAPI

final class CargoCacheMeasurement {
    let invocation: CargoCacheInvocation
    private var counters = Dictionary(uniqueKeysWithValues: CargoCacheReport.counters.map { ($0, UInt64(0)) })
    private var records: [[String: Any]] = []

    init(invocation: CargoCacheInvocation) {
        self.invocation = invocation
    }

    func outcome(hit: Bool) {
        counters[hit ? "hits" : "misses"] = 1
        records.append([
            "record": "task", "key": Self.key(invocation.key), "name": invocation.name,
            "kind": "rust", "status": hit ? "hit" : "miss",
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

    func failure(upload: Bool = false) {
        counters[upload ? "background_upload_failures" : "remote_failures", default: 0] += 1
    }

    func write() {
        guard let session = invocation.environment["TUIST_CARGO_SESSION"] else { return }
        let root = URL(fileURLWithPath: session)
        let id = UUID().uuidString
        let statistics = root.appendingPathComponent("cache-reports")
        let details = root.appendingPathComponent("cache-details")
        do {
            try FileManager.default.createDirectory(at: statistics, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: details, withIntermediateDirectories: true)
            var payload: [String: Any] = counters.mapValues { $0 as Any }
            payload["version"] = 1
            try JSONSerialization.data(withJSONObject: payload).write(
                to: statistics.appendingPathComponent(id + ".json"), options: .atomic
            )
            var data = Data()
            for record in records.prefix(500) {
                data.append(try JSONSerialization.data(withJSONObject: record))
                data.append(UInt8(10))
            }
            try data.write(to: details.appendingPathComponent(id + ".ndjson"), options: .atomic)
        } catch {}
    }

    private static func key(_ digest: REAPI.Digest) -> String {
        "sha256:\(digest.hash):\(digest.sizeBytes)"
    }

    private static func nanoseconds(_ duration: TimeInterval) -> UInt64 {
        UInt64(max(0, min(duration * 1_000_000_000, 9_000_000_000_000_000)))
    }
}
