import Command
import Foundation
import Testing

public enum Simulator {
    @TaskLocal public static var testing: String?
}

public struct SimulatorTestingTrait: TestTrait, SuiteTrait, TestScoping {
    let simulator: String

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let commandRunner = CommandRunner()
        let simulatorId = UUID().uuidString
        try await commandRunner.run(arguments: ["/usr/bin/xcrun", "simctl", "create", simulatorId, simulator]).awaitCompletion()
        try await Simulator.$testing.withValue("'name=\(simulatorId)'") {
            let clean = {
                try? await commandRunner.run(arguments: ["/usr/bin/xcrun", "simctl", "delete", "'name=\(simulatorId)'"]).awaitCompletion()
            }
            do {
                try await function()
            } catch {
                await clean()
                throw error
            }
            await clean()
        }
    }
}

extension Trait where Self == SimulatorTestingTrait {
    public static func withTestingSimulator(_ simulator: String) -> Self {
        return Self(simulator: simulator)
    }
}
