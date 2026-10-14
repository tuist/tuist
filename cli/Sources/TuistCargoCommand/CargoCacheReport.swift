import Foundation

enum CargoCacheReport {
    static let counters = [
        "hits", "misses", "unconsulted", "verifications", "divergences", "prefetched_actions",
        "downloaded_bytes", "uploaded_bytes", "remote_failures", "background_upload_failures",
        "estimated_compiler_duration_avoided_ns", "prefetch_duration_ns", "materialization_duration_ns",
        "remote_action_lookup_duration_ns", "remote_blob_transfer_duration_ns", "upload_drain_duration_ns",
    ]

    private struct NativeReport: Decodable {
        let version: Int
        let values: [String: UInt64]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            version = try container.decode(Int.self, forKey: Key("version"))
            values = try Dictionary(uniqueKeysWithValues: CargoCacheReport.counters.map {
                ($0, try container.decode(UInt64.self, forKey: Key($0)))
            })
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue _: Int) { return nil }
    }

    static func read(root: URL) -> [String: Any]? {
        let directory = root.appendingPathComponent("cache-reports")
        guard let files = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return nil }
        var result = Dictionary(uniqueKeysWithValues: counters.map { ($0, UInt64(0)) })
        var reports = 0
        var inspected = 0
        var remaining = 8_000_000
        for case let file as URL in files {
            guard inspected < 64, remaining > 0 else { break }
            inspected += 1
            guard file.pathExtension == "json",
                  let properties = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let size = properties.fileSize, size >= 0, size <= 512_000, size <= remaining,
                  let handle = try? FileHandle(forReadingFrom: file)
            else { continue }
            let data = try? handle.read(upToCount: min(512_001, remaining))
            try? handle.close()
            guard let data else { continue }
            remaining -= data.count
            guard data.count <= 512_000, data.count == size,
                  let report = try? JSONDecoder().decode(NativeReport.self, from: data), report.version == 5
            else { continue }
            reports += 1
            for (key, value) in report.values {
                let sum = result[key, default: 0].addingReportingOverflow(value)
                result[key] = min(sum.overflow ? UInt64.max : sum.partialValue, 9_000_000_000_000_000)
            }
        }
        guard reports > 0 else { return nil }
        var payload: [String: Any] = result.mapValues { $0 as Any }
        payload["version"] = 1
        if var details = CargoCacheDetailsReport.read(root: root) {
            let expected = ["hits", "misses", "unconsulted"].reduce(UInt64(0)) { $0 + result[$1, default: 0] }
            if let tasks = details["tasks"] as? [[String: Any]], UInt64(tasks.count) < expected { details["truncated"] = true }
            payload["details"] = details
        }
        return payload
    }
}
