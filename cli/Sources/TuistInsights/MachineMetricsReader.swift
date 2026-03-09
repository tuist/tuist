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

        guard let data = FileManager.default.contents(atPath: filePath.pathString),
              let content = String(data: data, encoding: .utf8)
        else { return [] }

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
}
