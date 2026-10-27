import Foundation
import TuistEnvironment
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
        let label = Environment.current.metricsSamplerLaunchAgentLabel()
        try await launchAgentService.setupLaunchAgent(
            label: label,
            plistFileName: "\(label).plist",
            programArguments: ["sample-host-metrics"],
            environmentVariables: [:]
        )

        Logger.current.info("Metrics sampling daemon has been set up successfully", metadata: .success)
    }
}
