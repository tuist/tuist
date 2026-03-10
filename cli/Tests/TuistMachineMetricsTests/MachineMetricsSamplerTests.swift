#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Path
    import Testing
    import TuistEnvironment
    import TuistEnvironmentTesting
    import TuistTesting

    @testable import TuistMachineMetrics

    @Suite(.serialized)
    struct MachineMetricsSamplerTests {
        private let fileSystem = FileSystem()

        @Test(.inTemporaryDirectory, .withMockedEnvironment(), .timeLimit(.minutes(1)))
        func sampler_writesSamplesToFile() async throws {
            let sampler = MachineMetricsSampler()
            let metricsPath = MachineMetricsReader.metricsFilePath

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .seconds(3))
            task.cancel()

            let content = try String(contentsOfFile: metricsPath.pathString, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            #expect(lines.count >= 2)

            let decoder = JSONDecoder()
            let sample = try decoder.decode(
                MachineMetricSample.self,
                from: Data(lines.first!.utf8)
            )

            #expect(sample.cpuUsagePercent >= 0)
            #expect(sample.cpuUsagePercent <= 100)
            #expect(sample.memoryTotalBytes > 0)
            #expect(sample.memoryUsedBytes > 0)
            #expect(sample.memoryUsedBytes <= sample.memoryTotalBytes)
            #expect(sample.timestamp > 0)
        }

        @Test(.inTemporaryDirectory, .withMockedEnvironment(), .timeLimit(.minutes(1)))
        func sampler_producesIncreasingTimestamps() async throws {
            let sampler = MachineMetricsSampler()
            let metricsPath = MachineMetricsReader.metricsFilePath

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .seconds(3))
            task.cancel()

            let content = try String(contentsOfFile: metricsPath.pathString, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            #expect(lines.count >= 2)

            let decoder = JSONDecoder()
            let samples = try lines.map { line in
                try decoder.decode(MachineMetricSample.self, from: Data(line.utf8))
            }

            for i in 1 ..< samples.count {
                #expect(samples[i].timestamp > samples[i - 1].timestamp)
            }
        }

        @Test(.inTemporaryDirectory, .withMockedEnvironment(), .timeLimit(.minutes(1)))
        func sampler_networkAndDiskDeltasAreNonNegative() async throws {
            let sampler = MachineMetricsSampler()
            let metricsPath = MachineMetricsReader.metricsFilePath

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .seconds(3))
            task.cancel()

            let content = try String(contentsOfFile: metricsPath.pathString, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

            let decoder = JSONDecoder()
            let samples = try lines.map { line in
                try decoder.decode(MachineMetricSample.self, from: Data(line.utf8))
            }

            for sample in samples {
                #expect(sample.networkBytesIn >= 0)
                #expect(sample.networkBytesOut >= 0)
                #expect(sample.diskBytesRead >= 0)
                #expect(sample.diskBytesWritten >= 0)
            }
        }

        @Test(.inTemporaryDirectory, .withMockedEnvironment(), .timeLimit(.minutes(1)))
        func sampler_createsFileIfNeeded() async throws {
            let sampler = MachineMetricsSampler()
            let metricsPath = MachineMetricsReader.metricsFilePath

            #expect(try await !fileSystem.exists(metricsPath))

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .seconds(2))
            task.cancel()

            #expect(try await fileSystem.exists(metricsPath))
        }

        @Test(.inTemporaryDirectory, .withMockedEnvironment(), .timeLimit(.minutes(1)))
        func sampler_appendsToExistingFile() async throws {
            let sampler = MachineMetricsSampler()
            let metricsPath = MachineMetricsReader.metricsFilePath

            let existingSample = MachineMetricSample(
                timestamp: 1000,
                cpuUsagePercent: 42,
                memoryUsedBytes: 1,
                memoryTotalBytes: 2,
                networkBytesIn: 0,
                networkBytesOut: 0,
                diskBytesRead: 0,
                diskBytesWritten: 0
            )
            let encoder = JSONEncoder()
            let existingLine = String(data: try encoder.encode(existingSample), encoding: .utf8)!

            let dir = metricsPath.parentDirectory.pathString
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try existingLine.appending("\n").write(toFile: metricsPath.pathString, atomically: false, encoding: .utf8)

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .seconds(2))
            task.cancel()

            let data = try Data(contentsOf: URL(fileURLWithPath: metricsPath.pathString))
            let content = String(data: data, encoding: .utf8)!
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            #expect(lines.count >= 2)

            let decoder = JSONDecoder()
            let firstSample = try decoder.decode(MachineMetricSample.self, from: Data(lines.first!.utf8))
            #expect(firstSample.timestamp == 1000)
        }
    }
#endif
