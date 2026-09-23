import Foundation
import Noora
import TuistServer

protocol RunnerVolumeShowCommandServicing {
    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws
}

struct RunnerVolumeShowCommandService: RunnerVolumeShowCommandServicing {
    private let contextService: RunnerVolumeContextServicing
    private let getRunnerVolumeService: GetRunnerVolumeServicing

    init(
        contextService: RunnerVolumeContextServicing = RunnerVolumeContextService(),
        getRunnerVolumeService: GetRunnerVolumeServicing = GetRunnerVolumeService()
    ) {
        self.contextService = contextService
        self.getRunnerVolumeService = getRunnerVolumeService
    }

    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws {
        let context = try await contextService.resolve(account: account, path: path)
        let response = try await getRunnerVolumeService.getRunnerVolume(
            accountHandle: context.accountHandle,
            serverURL: context.serverURL,
            volumeID: volumeID
        )
        if json {
            try Noora.current.json(response)
        } else {
            Noora.current.passthrough("\(RunnerVolumeOutput.details(response))")
        }
    }
}
