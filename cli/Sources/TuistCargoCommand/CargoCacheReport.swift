import Foundation

enum CargoCacheReport {
    static let counters = [
        "hits", "misses", "unconsulted", "verifications", "divergences", "prefetched_actions",
        "downloaded_bytes", "uploaded_bytes", "remote_failures", "background_upload_failures",
        "estimated_compiler_duration_avoided_ns", "prefetch_duration_ns", "materialization_duration_ns",
        "remote_action_lookup_duration_ns", "remote_blob_transfer_duration_ns", "upload_drain_duration_ns",
    ]

    /// The counters of a version-1 measurement, every one present as an unsigned integer. Read with
    /// `JSONSerialization` rather than `JSONDecoder`, whose first decodes of a type cost more in runtime type lookups
    /// than these few small files take to read.
    private static func measurement(_ data: Data) -> [String: UInt64]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              unsigned(object["version"]) == 1 else { return nil }
        var values: [String: UInt64] = [:]
        for counter in counters {
            guard let value = unsigned(object[counter]) else { return nil }
            values[counter] = value
        }
        return values
    }

    /// A JSON number that is an unsigned integer, as `JSONDecoder` decodes `UInt64`: not a boolean, a fraction, a
    /// negative number or a string.
    static func unsigned(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber, !["c", "C", "B"].contains(String(cString: number.objCType)) else { return nil }
        return UInt64(number.stringValue, radix: 10)
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
        var truncated = false
        var remaining = 8_000_000
        for case let file as URL in files {
            guard inspected < 4096, remaining > 0 else { truncated = true; break }
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
                  let values = measurement(data)
            else { continue }
            reports += 1
            for (key, value) in values {
                let sum = result[key, default: 0].addingReportingOverflow(value)
                result[key] = min(sum.overflow ? UInt64.max : sum.partialValue, 9_000_000_000_000_000)
            }
        }
        guard reports > 0 else { return nil }
        var payload: [String: Any] = result.mapValues { $0 as Any }
        payload["version"] = 1
        if var details = CargoCacheDetailsReport.read(root: root) {
            let expected = ["hits", "misses", "unconsulted"].reduce(UInt64(0)) { $0 + result[$1, default: 0] }
            if truncated { details["truncated"] = true }
            if let tasks = details["tasks"] as? [[String: Any]], UInt64(tasks.count) < expected { details["truncated"] = true }
            payload["details"] = details
        }
        return payload
    }
}
