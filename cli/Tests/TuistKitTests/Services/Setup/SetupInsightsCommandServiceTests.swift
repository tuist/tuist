import Foundation
import Mockable
import Testing
import TuistEnvironment
import TuistLaunchctl
import TuistLoggerTesting
import TuistTesting

@testable import TuistKit

struct SetupInsightsCommandServiceTests {
    private let subject: SetupInsightsCommandService
    private let launchAgentService = MockLaunchAgentServicing()

    init() {
        subject = SetupInsightsCommandService(
            launchAgentService: launchAgentService
        )

        given(launchAgentService)
            .setupLaunchAgent(
                label: .any,
                plistFileName: .any,
                programArguments: .any,
                environmentVariables: .any
            )
            .willReturn()
    }

    @Test(.withMockedEnvironment(), .withMockedLogger()) func setupInsights() async throws {
        // When
        try await subject.run()

        // Then: the label has to match the one `tuist teardown insights` boots out.
        verify(launchAgentService)
            .setupLaunchAgent(
                label: .value("tuist.metrics-sampler"),
                plistFileName: .value("tuist.metrics-sampler.plist"),
                programArguments: .value(["sample-host-metrics"]),
                environmentVariables: .value([:])
            )
            .called(1)

        TuistTest.expectLogs("Metrics sampling daemon has been set up successfully")
    }
}
