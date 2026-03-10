import Foundation
import TuistLaunchctl
import TuistLogging

struct SetupInsightsCommandService {
    private let launchAgentService: LaunchAgentServicing

    init(
        launchAgentService: LaunchAgentServicing = LaunchAgentService()
    ) {
        self.launchAgentService = launchAgentService
    }

    func run() async throws {
        try await launchAgentService.setupLaunchAgent(
            label: "tuist.metrics-sampler",
            plistFileName: "tuist.metrics-sampler.plist",
            programArguments: ["sample-host-metrics"],
            environmentVariables: [:]
        )

        Logger.current.info("Metrics sampling daemon has been set up successfully", metadata: .success)
    }
}
