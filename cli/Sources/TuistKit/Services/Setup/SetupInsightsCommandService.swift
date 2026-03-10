import Foundation
import TuistLaunchctl
import TuistLogging

struct SetupInsightsCommandService {
    private let launchAgentService: LaunchAgentService

    init(
        launchAgentService: LaunchAgentService = LaunchAgentService()
    ) {
        self.launchAgentService = launchAgentService
    }

    func run() async throws {
        try await launchAgentService.setupLaunchAgent(
            label: "tuist.insights",
            plistFileName: "tuist.insights.plist",
            programArguments: ["insights-start"]
        )

        Logger.current.info("Insights daemon has been set up successfully", metadata: .success)
    }
}
