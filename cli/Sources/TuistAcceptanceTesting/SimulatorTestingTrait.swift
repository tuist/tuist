import Command
import Foundation
import Testing

public struct Simulator: CustomStringConvertible {
    @TaskLocal public static var testing: Simulator?

    public let name: String

    public var description: String {
        "name=\(name)"
    }
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
        try await commandRunner.run(arguments: ["/usr/bin/xcrun", "simctl", "create", simulatorId, simulator]).pipedStream()
            .awaitCompletion()
        try await Simulator.$testing.withValue(Simulator(name: simulatorId)) {
            let clean = {
                try await commandRunner.run(arguments: ["/usr/bin/xcrun", "simctl", "delete", simulatorId])
                    .pipedStream()
                    .awaitCompletion()
            }
            do {
                try await function()
            } catch {
                try await clean()
                throw error
            }
            try await clean()
        }
    }
}

extension Trait where Self == SimulatorTestingTrait {
    public static func withTestingSimulator(_ simulator: String) -> Self {
        return Self(simulator: simulator)
    }
}
