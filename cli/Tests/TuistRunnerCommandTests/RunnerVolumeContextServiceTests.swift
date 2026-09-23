import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer
@testable import TuistRunnerCommand

struct RunnerVolumeContextServiceTests {
    @Test(.withMockedEnvironment(), arguments: [false, true])
    func resolvesConfiguredAccountUnlessOverridden(override: Bool) async throws {
        let configLoader = MockConfigLoading()
        let serverEnvironment = MockServerEnvironmentServicing()
        let config = Tuist.test(fullHandle: "configured/project")
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let serverURL = URL(string: "https://custom.tuist.dev")!
        given(configLoader).loadConfig(path: .value(directory)).willReturn(config)
        given(serverEnvironment).url(configServerURL: .value(config.url)).willReturn(serverURL)
        let subject = RunnerVolumeContextService(configLoader: configLoader, serverEnvironmentService: serverEnvironment)

        let context = try await subject.resolve(account: override ? "explicit" : nil, path: nil)

        #expect(context.accountHandle == (override ? "explicit" : "configured"))
        #expect(context.serverURL == serverURL)
    }

    @Test(.withMockedEnvironment())
    func rejectsMissingAccount() async throws {
        let configLoader = MockConfigLoading()
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directory)).willReturn(.test(fullHandle: nil))
        let subject = RunnerVolumeContextService(configLoader: configLoader)

        await #expect(throws: RunnerVolumeContextServiceError.missingAccount) {
            try await subject.resolve(account: nil, path: nil)
        }
    }
}
