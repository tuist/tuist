import FileSystem
import Foundation
import Path
@preconcurrency import TSCBasic
import TuistEnvironment

public struct MachineMetricsReader {
    public static var metricsFilePath: Path.AbsolutePath {
        Environment.current.stateDirectory
            .appending(component: "machine_metrics.jsonl")
    }

    private let fileSystem: FileSysteming

    public init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    public func readSamples(
        startDate: Date,
        endDate: Date,
        maxCount: Int = 3600
    ) async throws -> [MachineMetricSample] {
        let startTimestamp = startDate.timeIntervalSince1970
        let endTimestamp = endDate.timeIntervalSince1970

        guard try await fileSystem.exists(Self.metricsFilePath) else { return [] }

        let lockPath = Self.metricsFilePath.pathString + ".lock"
        let fileLock = TSCBasic.FileLock(
            at: try TSCBasic.AbsolutePath(validating: lockPath)
        )

        let content: String = try await fileLock.withLock(type: .shared) {
            try await fileSystem.readTextFile(at: Self.metricsFilePath)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        let samples = lines.compactMap { line -> MachineMetricSample? in
            guard let lineData = line.data(using: .utf8),
                  let sample = try? decoder.decode(MachineMetricSample.self, from: lineData)
            else { return nil }
            guard sample.timestamp >= startTimestamp, sample.timestamp <= endTimestamp else { return nil }
            return sample
        }

        return downsample(samples, maxCount: maxCount)
    }

    private func downsample(_ samples: [MachineMetricSample], maxCount: Int) -> [MachineMetricSample] {
        guard samples.count > maxCount, maxCount >= 2 else { return samples }
        let step = Double(samples.count - 1) / Double(maxCount - 1)
        return (0 ..< maxCount).map { i in
            samples[min(Int(Double(i) * step), samples.count - 1)]
        }
    }
}
