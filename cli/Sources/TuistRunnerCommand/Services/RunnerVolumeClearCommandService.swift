import Foundation
import Noora
import TuistServer

protocol RunnerVolumeClearCommandServicing {
    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws
}

struct RunnerVolumeClearCommandService: RunnerVolumeClearCommandServicing {
    private let contextService: RunnerVolumeContextServicing
    private let clearRunnerVolumeService: ClearRunnerVolumeServicing

    init(
        contextService: RunnerVolumeContextServicing = RunnerVolumeContextService(),
        clearRunnerVolumeService: ClearRunnerVolumeServicing = ClearRunnerVolumeService()
    ) {
        self.contextService = contextService
        self.clearRunnerVolumeService = clearRunnerVolumeService
    }

    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws {
        let context = try await contextService.resolve(account: account, path: path)
        let response = try await clearRunnerVolumeService.clearRunnerVolume(
            accountHandle: context.accountHandle,
            serverURL: context.serverURL,
            volumeID: volumeID
        )
        if json {
            try Noora.current.json(response)
        } else {
            Noora.current.success("Saved contents cleared for volume \(volumeID).")
        }
    }
}
