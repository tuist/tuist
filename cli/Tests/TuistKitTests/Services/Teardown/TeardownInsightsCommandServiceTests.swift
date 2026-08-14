import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistEnvironment
import TuistLaunchctl
import TuistLoggerTesting
import TuistMachineMetrics
import TuistTesting

@testable import TuistKit

struct TeardownInsightsCommandServiceTests {
    private let subject: TeardownInsightsCommandService
    private let launchAgentService = MockLaunchAgentServicing()
    private let fileSystem = FileSystem()

    init() {
        subject = TeardownInsightsCommandService(
            launchAgentService: launchAgentService,
            fileSystem: FileSystem()
        )

        given(launchAgentService)
            .teardownLaunchAgent(label: .any, plistFileName: .any)
            .willReturn()
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), .withMockedLogger()) func teardownInsights() async throws {
        // When
        try await subject.run()

        // Then
        verify(launchAgentService)
            .teardownLaunchAgent(
                label: .value("tuist.metrics-sampler"),
                plistFileName: .value("tuist.metrics-sampler.plist")
            )
            .called(1)

        TuistTest.expectLogs("Insights daemon has been torn down 🧹")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func teardownInsights_removesSampledMetricsAndLogsWhenPresent() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        let metricsFilePath = MachineMetricsReader.metricsFilePath
        let lockPath = metricsFilePath.parentDirectory
            .appending(component: "\(metricsFilePath.basename).lock")
        let stdoutLogPath = environment.stateDirectory
            .appending(component: "tuist.metrics-sampler.stdout.log")
        let stderrLogPath = environment.stateDirectory
            .appending(component: "tuist.metrics-sampler.stderr.log")
        for path in [metricsFilePath, lockPath, stdoutLogPath, stderrLogPath] {
            try await fileSystem.writeText("", at: path)
        }

        // When
        try await subject.run()

        // Then
        for path in [metricsFilePath, lockPath, stdoutLogPath, stderrLogPath] {
            let exists = try await fileSystem.exists(path)
            #expect(exists == false)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func teardownInsights_succeedsWhenSampledMetricsMissing() async throws {
        // When / Then
        try await subject.run()

        verify(launchAgentService)
            .teardownLaunchAgent(
                label: .value("tuist.metrics-sampler"),
                plistFileName: .value("tuist.metrics-sampler.plist")
            )
            .called(1)
    }
}
