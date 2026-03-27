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

    /// Integration tests that run the real sampler daemon loop. Sleeps are required
    /// because the sampler collects metrics via actual macOS system calls.
    @Suite
    struct MachineMetricsSamplerTests {
        private let fileSystem = FileSystem()

        @Test(.inTemporaryDirectory, .timeLimit(.minutes(1)))
        func sampler_writesSamplesToFile() async throws {
            let metricsPath = try metricsFilePath()
            let sampler = MachineMetricsSampler(metricsFilePath: metricsPath, interval: .milliseconds(100))

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .milliseconds(350))
            task.cancel()

            let content = try String(contentsOfFile: metricsPath.pathString, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            #expect(lines.count >= 2)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
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

        @Test(.inTemporaryDirectory, .timeLimit(.minutes(1)))
        func sampler_producesIncreasingTimestamps() async throws {
            let metricsPath = try metricsFilePath()
            let sampler = MachineMetricsSampler(metricsFilePath: metricsPath, interval: .milliseconds(100))

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .milliseconds(350))
            task.cancel()

            let content = try String(contentsOfFile: metricsPath.pathString, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            #expect(lines.count >= 2)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let samples = try lines.map { line in
                try decoder.decode(MachineMetricSample.self, from: Data(line.utf8))
            }

            for i in 1 ..< samples.count {
                #expect(samples[i].timestamp > samples[i - 1].timestamp)
            }
        }

        @Test(.inTemporaryDirectory, .timeLimit(.minutes(1)))
        func sampler_networkAndDiskDeltasAreNonNegative() async throws {
            let metricsPath = try metricsFilePath()
            let sampler = MachineMetricsSampler(metricsFilePath: metricsPath, interval: .milliseconds(100))

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .milliseconds(350))
            task.cancel()

            let content = try String(contentsOfFile: metricsPath.pathString, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
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

        @Test(.inTemporaryDirectory, .timeLimit(.minutes(1)))
        func sampler_createsFileIfNeeded() async throws {
            let metricsPath = try metricsFilePath()
            let sampler = MachineMetricsSampler(metricsFilePath: metricsPath, interval: .milliseconds(100))

            #expect(try await !fileSystem.exists(metricsPath))

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .milliseconds(250))
            task.cancel()

            #expect(try await fileSystem.exists(metricsPath))
        }

        @Test(.inTemporaryDirectory, .timeLimit(.minutes(1)))
        func sampler_appendsToExistingFile() async throws {
            let metricsPath = try metricsFilePath()
            let sampler = MachineMetricsSampler(metricsFilePath: metricsPath, interval: .milliseconds(100))

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
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let existingLine = String(data: try encoder.encode(existingSample), encoding: .utf8)!

            try await fileSystem.makeDirectory(at: metricsPath.parentDirectory)
            try await fileSystem.writeText(existingLine.appending("\n"), at: metricsPath)

            let task = Task {
                try await sampler.run()
            }

            try await Task.sleep(for: .milliseconds(250))
            task.cancel()

            let content = try String(contentsOfFile: metricsPath.pathString, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            #expect(lines.count >= 2)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let firstSample = try decoder.decode(MachineMetricSample.self, from: Data(lines.first!.utf8))
            #expect(firstSample.timestamp == 1000)
        }

        private func metricsFilePath() throws -> Path.AbsolutePath {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            return temporaryDirectory.appending(component: "machine_metrics_\(UUID().uuidString).jsonl")
        }
    }
#endif
