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
            label: "tuist.insights",
            plistFileName: "tuist.insights.plist",
            programArguments: ["insights-start"],
            environmentVariables: [:]
        )

        Logger.current.info("Insights daemon has been set up successfully", metadata: .success)
    }
}
