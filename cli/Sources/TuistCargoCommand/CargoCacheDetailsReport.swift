import Foundation

/// Public cache inspection records, never the engine's private event stream.
enum CargoCacheDetailsReport {
    private struct Record: Decodable {
        let record: String
        let key: String
        let name: String?
        let kind: String?
        let status: String?
        let operation: String?
        let durationNanoseconds: UInt64?
        let sizeBytes: UInt64?
        let object: String?

        private enum CodingKeys: String, CodingKey {
            case record, key, name, kind, status, operation, object
            case durationNanoseconds = "duration_ns"
            case sizeBytes = "size_bytes"
        }
    }

    static func read(root: URL) -> [String: Any]? {
        let directory = root.appendingPathComponent("cache-details")
        guard let entries = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return nil }
        var tasks: [[String: Any]] = []
        var objects: [[String: Any]] = []
        var timings: [String: [String: Double]] = [:]
        var timingCounts: [String: [String: UInt64]] = [:]
        var referenceCount = 0
        var adapters: [String: String] = [:]
        var references: [String: Set<String>] = [:]
        var truncated = FileManager.default.fileExists(atPath: directory.appendingPathComponent("truncated").path)
        var remaining = 8_000_000
        var candidates: [URL] = []
        var inspected = 0
        for case let file as URL in entries {
            guard inspected < 64 else { truncated = true; break }
            inspected += 1
            if file.pathExtension == "ndjson" { candidates.append(file) }
        }
        candidates.sort { $0.lastPathComponent < $1.lastPathComponent }
        var records = 0
        for file in candidates.prefix(64) {
            guard remaining > 0,
                  let properties = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let size = properties.fileSize, size >= 0, size <= remaining,
                  let handle = try? FileHandle(forReadingFrom: file) else { truncated = true; continue }
            let data = try? handle.read(upToCount: min(8_000_001, remaining + 1))
            try? handle.close()
            guard let data else { truncated = true; continue }
            remaining -= min(data.count, remaining)
            guard data.count == size, data.count <= 8_000_000 else { truncated = true; continue }
            for line in data.split(separator: UInt8(10), maxSplits: 30000, omittingEmptySubsequences: true) {
                guard records < 30000 else { truncated = true; break }
                records += 1
                guard line.count <= 8192, let row = try? JSONDecoder().decode(Record.self, from: Data(line)), validKey(row.key)
                else { truncated = true; continue }
                switch row.record {
                case "task":
                    guard tasks.count < 2000, let name = row.name, !name.isEmpty, name.utf8.count <= 1024,
                          let kind = row.kind, ["rust", "compiler", "build_script"].contains(kind), let status = row.status,
                          ["hit", "miss", "unconsulted", "verification"].contains(status)
                    else { truncated = true; continue }
                    tasks.append(["key": row.key, "name": name, "kind": kind, "status": status])
                case "adapter":
                    guard adapters.count < 2000, row.kind == "build_script" else { truncated = true; continue }
                    adapters[row.key] = row.kind
                case "timing":
                    guard timings.count < 5000, let operation = row.operation, ["read", "write"].contains(operation),
                          let duration = row.durationNanoseconds, duration <= 9_000_000_000_000_000
                    else { truncated = true; continue }
                    let previous = timings[row.key, default: [:]][operation, default: 0]
                    timings[row.key, default: [:]][operation] = previous + Double(duration)
                    timingCounts[row.key, default: [:]][operation, default: 0] += 1
                case "reference":
                    guard references.count < 2000, referenceCount < 10000, let object = row.object, validKey(object),
                          references[row.key, default: []].count < 128
                    else { truncated = true; continue }
                    if references[row.key, default: []].insert(object).inserted { referenceCount += 1 }
                case "cas":
                    guard objects.count < 5000, let operation = row.operation, ["download", "upload"].contains(operation),
                          let status = row.status,
                          (operation == "download" ? ["downloaded", "failed"] : ["uploaded", "present", "failed"])
                          .contains(status),
                          row.key.hasPrefix("sha256:"), let size = row.sizeBytes, size <= 9_000_000_000_000_000,
                          let duration = row.durationNanoseconds, duration <= 9_000_000_000_000_000
                    else { truncated = true; continue }
                    objects.append([
                        "key": row.key,
                        "operation": operation,
                        "status": status,
                        "size_bytes": size,
                        "duration_ns": duration,
                    ])
                default: truncated = true
                }
            }
        }
        guard !candidates.isEmpty else { return nil }
        tasks = tasks.map { task in
            var task = task
            guard let key = task["key"] as? String else { return task }
            if let adapter = adapters[key] { task["kind"] = adapter }
            task["cas_keys"] = Array(references[key, default: []]).sorted()
            for (operation, duration) in timings[key, default: [:]] {
                task["\(operation)_duration_ns"] = UInt64(min(
                    duration / Double(max(timingCounts[key, default: [:]][operation, default: 0], 1)),
                    9_000_000_000_000_000
                ))
            }
            return task
        }
        var payload: [String: Any] = ["version": 1, "tasks": tasks, "cas_outputs": objects, "truncated": truncated]
        while let data = try? JSONSerialization.data(withJSONObject: payload), data.count > 4_000_000 {
            tasks = Array(tasks.prefix(tasks.count / 2))
            objects = Array(objects.prefix(objects.count / 2))
            payload = ["version": 1, "tasks": tasks, "cas_outputs": objects, "truncated": true]
        }
        return payload
    }

    private static func validKey(_ value: String) -> Bool {
        value.range(of: "^(blake3|sha256):[0-9a-f]{64}:[0-9]{1,20}$", options: .regularExpression) != nil
    }
}
