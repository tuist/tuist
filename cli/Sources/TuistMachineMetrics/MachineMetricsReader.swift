#if os(macOS)
    import Darwin
#endif
import Foundation
import Path
import TuistEnvironment

public struct MachineMetricsReader {
    public static let metricsFilePath: AbsolutePath = Environment.current.stateDirectory
        .appending(component: "machine_metrics.jsonl")

    public init() {}

    public func readSamples(
        startDate: Date,
        endDate: Date,
        maxCount: Int = 3600
    ) -> [MachineMetricSample] {
        let startTimestamp = startDate.timeIntervalSince1970
        let endTimestamp = endDate.timeIntervalSince1970

        guard let data = withSharedFileLock(Self.metricsFilePath, {
            FileManager.default.contents(atPath: Self.metricsFilePath.pathString) ?? Data()
        }), let content = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        let samples = lines.compactMap { line -> MachineMetricSample? in
            guard let lineData = line.data(using: .utf8),
                  let sample = try? decoder.decode(MachineMetricSample.self, from: lineData)
            else { return nil }
            guard sample.timestamp >= startTimestamp, sample.timestamp <= endTimestamp else { return nil }
            return sample
        }

        return Self.downsample(samples, maxCount: maxCount)
    }

    static func downsample(_ samples: [MachineMetricSample], maxCount: Int) -> [MachineMetricSample] {
        guard samples.count > maxCount, maxCount >= 2 else { return samples }
        let step = Double(samples.count - 1) / Double(maxCount - 1)
        return (0 ..< maxCount).map { i in
            samples[min(Int(Double(i) * step), samples.count - 1)]
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
