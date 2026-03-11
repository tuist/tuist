import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistEnvironment
import TuistEnvironmentTesting
import TuistTesting

@testable import TuistMachineMetrics

struct MachineMetricsReaderTests {
    private let fileSystem = FileSystem()

    private func writeSamples(_ samples: [MachineMetricSample]) async throws {
        let encoder = JSONEncoder()
        let lines = try samples.map { sample in
            let data = try encoder.encode(sample)
            return String(data: data, encoding: .utf8)!
        }
        let content = lines.joined(separator: "\n") + "\n"
        let path = MachineMetricsReader.metricsFilePath
        if try await !fileSystem.exists(path.parentDirectory) {
            try await fileSystem.makeDirectory(at: path.parentDirectory)
        }
        try await fileSystem.writeText(content, at: path)
    }

    private func makeSample(timestamp: Double, cpuUsagePercent: Double = 50.0) -> MachineMetricSample {
        MachineMetricSample(
            timestamp: timestamp,
            cpuUsagePercent: cpuUsagePercent,
            memoryUsedBytes: 8_000_000_000,
            memoryTotalBytes: 16_000_000_000,
            networkBytesIn: 1_000_000,
            networkBytesOut: 500_000,
            diskBytesRead: 2_000_000,
            diskBytesWritten: 1_500_000
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readSamples_returnsEmptyWhenFileDoesNotExist() async throws {
        let subject = MachineMetricsReader(fileSystem: fileSystem)

        let samples = try await subject.readSamples(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000)
        )

        #expect(samples.isEmpty)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readSamples_returnsSamplesWithinTimeRange() async throws {
        let subject = MachineMetricsReader(fileSystem: fileSystem)

        try await writeSamples([
            makeSample(timestamp: 1000, cpuUsagePercent: 10),
            makeSample(timestamp: 1500, cpuUsagePercent: 50),
            makeSample(timestamp: 2000, cpuUsagePercent: 90),
            makeSample(timestamp: 2500, cpuUsagePercent: 30),
        ])

        let samples = try await subject.readSamples(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000)
        )

        #expect(samples.count == 3)
        #expect(samples[0].cpuUsagePercent == 10)
        #expect(samples[1].cpuUsagePercent == 50)
        #expect(samples[2].cpuUsagePercent == 90)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readSamples_filtersOutSamplesOutsideTimeRange() async throws {
        let subject = MachineMetricsReader(fileSystem: fileSystem)

        try await writeSamples([
            makeSample(timestamp: 500),
            makeSample(timestamp: 1500),
            makeSample(timestamp: 3000),
        ])

        let samples = try await subject.readSamples(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000)
        )

        #expect(samples.count == 1)
        #expect(samples[0].timestamp == 1500)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readSamples_returnsEmptyForEmptyFile() async throws {
        let subject = MachineMetricsReader(fileSystem: fileSystem)

        let path = MachineMetricsReader.metricsFilePath
        if try await !fileSystem.exists(path.parentDirectory) {
            try await fileSystem.makeDirectory(at: path.parentDirectory)
        }
        try await fileSystem.writeText("", at: path)

        let samples = try await subject.readSamples(
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 9999)
        )

        #expect(samples.isEmpty)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readSamples_skipsInvalidLines() async throws {
        let subject = MachineMetricsReader(fileSystem: fileSystem)

        let validSample = makeSample(timestamp: 1500)
        let encoder = JSONEncoder()
        let validLine = String(data: try encoder.encode(validSample), encoding: .utf8)!
        let content = "not valid json\n\(validLine)\n{\"broken\": true}\n"

        let path = MachineMetricsReader.metricsFilePath
        if try await !fileSystem.exists(path.parentDirectory) {
            try await fileSystem.makeDirectory(at: path.parentDirectory)
        }
        try await fileSystem.writeText(content, at: path)

        let samples = try await subject.readSamples(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000)
        )

        #expect(samples.count == 1)
        #expect(samples[0].timestamp == 1500)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readSamples_downsamplesWhenExceedingMaxCount() async throws {
        let subject = MachineMetricsReader(fileSystem: fileSystem)

        let samples = (0 ..< 100).map { i in
            makeSample(timestamp: 1000 + Double(i), cpuUsagePercent: Double(i))
        }
        try await writeSamples(samples)

        let result = try await subject.readSamples(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 1099),
            maxCount: 10
        )

        #expect(result.count == 10)
        #expect(result.first?.timestamp == 1000)
        #expect(result.last?.timestamp == 1099)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readSamples_doesNotDownsampleWhenUnderMaxCount() async throws {
        let subject = MachineMetricsReader(fileSystem: fileSystem)

        let samples = (0 ..< 5).map { i in
            makeSample(timestamp: 1000 + Double(i))
        }
        try await writeSamples(samples)

        let result = try await subject.readSamples(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 1004),
            maxCount: 10
        )

        #expect(result.count == 5)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readSamples_inclusiveTimeRangeBoundaries() async throws {
        let subject = MachineMetricsReader(fileSystem: fileSystem)

        try await writeSamples([
            makeSample(timestamp: 1000),
            makeSample(timestamp: 2000),
        ])

        let samples = try await subject.readSamples(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000)
        )

        #expect(samples.count == 2)
    }
}
