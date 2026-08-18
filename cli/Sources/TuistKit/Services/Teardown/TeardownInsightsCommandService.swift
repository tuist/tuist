import FileSystem
import Foundation
import Path
import TuistEnvironment
import TuistLaunchctl
import TuistLogging
import TuistMachineMetrics

struct TeardownInsightsCommandService {
    private let launchAgentService: LaunchAgentServicing
    private let fileSystem: FileSysteming

    init(
        launchAgentService: LaunchAgentServicing = LaunchAgentService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.launchAgentService = launchAgentService
        self.fileSystem = fileSystem
    }

    func run() async throws {
        let label = Environment.current.metricsSamplerLaunchAgentLabel()
        try await launchAgentService.teardownLaunchAgent(
            label: label,
            plistFileName: "\(label).plist"
        )

        // The samples are only meaningful to a running daemon, and leaving them behind
        // means a later `tuist setup insights` appends to a file the daemon never wrote.
        let metricsFilePath = MachineMetricsReader.metricsFilePath
        let stateDirectory = Environment.current.stateDirectory
        let leftovers = [
            metricsFilePath,
            metricsFilePath.parentDirectory.appending(component: "\(metricsFilePath.basename).lock"),
            stateDirectory.appending(component: "\(label).stdout.log"),
            stateDirectory.appending(component: "\(label).stderr.log"),
        ]
        for path in leftovers {
            guard try await fileSystem.exists(path) else { continue }
            try await fileSystem.remove(path)
        }

        Logger.current.info("Insights daemon has been torn down 🧹", metadata: .success)
    }
}
