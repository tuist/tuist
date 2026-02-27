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

    private static let fallbackSimulator = "iPhone 17"

    private static func defaultSimulatorName() -> String {
        if let value = ProcessInfo.processInfo.environment["TUIST_ACCEPTANCE_SIMULATOR_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false
        {
            return value
        }
        return fallbackSimulator
    }

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let checkout = try await SimulatorPool.shared.checkout(requestedSimulator: simulator)
        try await Simulator.$testing.withValue(Simulator(name: checkout.identifier)) {
            do {
                try await function()
            } catch {
                await SimulatorPool.shared.release(identifier: checkout.identifier, model: checkout.model)
                throw error
            }
            await SimulatorPool.shared.release(identifier: checkout.identifier, model: checkout.model)
        }
    }
}

extension Trait where Self == SimulatorTestingTrait {
    public static func withTestingSimulator(_ simulator: String? = nil) -> Self {
        return Self(simulator: simulator ?? SimulatorTestingTrait.defaultSimulatorName())
    }
}
