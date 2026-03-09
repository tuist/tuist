#if os(macOS)
    import Darwin
#endif
import Foundation
import Path

public struct MachineMetricsReader {
    public init() {}

    public func readSamples(
        from filePath: AbsolutePath,
        startDate: Date,
        endDate: Date
    ) -> [MachineMetricSample] {
        let startTimestamp = startDate.timeIntervalSince1970
        let endTimestamp = endDate.timeIntervalSince1970

        let content: String? = withSharedFileLock(filePath) {
            guard let data = FileManager.default.contents(atPath: filePath.pathString),
                  let str = String(data: data, encoding: .utf8)
            else { return nil }
            return str
        }

        guard let content else { return [] }

        let decoder = JSONDecoder()
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        return lines.compactMap { line -> MachineMetricSample? in
            guard let lineData = line.data(using: .utf8),
                  let sample = try? decoder.decode(MachineMetricSample.self, from: lineData)
            else { return nil }
            guard sample.timestamp >= startTimestamp, sample.timestamp <= endTimestamp else { return nil }
            return sample
        }
    }

    private func withSharedFileLock<T>(_ filePath: AbsolutePath, _ body: () -> T) -> T? {
        let lockPath = filePath.pathString + ".lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard flock(fd, LOCK_SH) == 0 else { return nil }
        defer { flock(fd, LOCK_UN) }
        return body()
    }
}
