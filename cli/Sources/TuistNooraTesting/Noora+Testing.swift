import Foundation
import Logging
import Noora
import Testing
import TuistAlert
import TuistLoggerTesting
import TuistLogging

extension Noora {
    public static var mocked: NooraMock? { current as? NooraMock }
}

public struct NooraTestingTrait: TestTrait, SuiteTrait, TestScoping {
    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let (logger, handler) = Logger.initTestingLogger()
        try await Logger.$current.withValue(logger) {
            try await Logger.$testingLogHandler.withValue(handler) {
                try await Noora.$current.withValue(NooraMock(terminal: Terminal(isInteractive: false))) {
                    try await AlertController.$current.withValue(AlertController()) {
                        try await function()
                    }
                }
            }
        }
    }
}

extension Trait where Self == NooraTestingTrait {
    /// When this trait is applied, it uses a mock for the task local `Noora.current`.`
    public static var withMockedNoora: Self { Self() }
}

public func resetUI() {
    AlertController.current.reset()
    Noora.mocked?.reset()
}

public func ui() -> String {
    AlertController.current.print()
    let nooraOutput = Noora.mocked?.description ?? ""
    let loggerOutput = Logger.testingLogHandler.collected[.warning, >=]
    let combined = [nooraOutput, loggerOutput].filter { !$0.isEmpty }.joined(separator: "\n")
    return combined.replacingOccurrences(
        of: #"\[[0-9]+(?:\.[0-9]+)?s\]"#,
        with: "[0.0s]",
        options: .regularExpression
    )
}
