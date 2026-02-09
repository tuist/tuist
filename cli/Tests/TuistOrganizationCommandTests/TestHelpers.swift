import Foundation
import Logging
import Noora
import Testing
import TuistAlert
import TuistLogging

extension URL {
    static func test() -> URL {
        URL(string: "https://test.tuist.io")!
    }
}

struct NooraTestingTrait: TestTrait, SuiteTrait, TestScoping {
    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await Noora.$current.withValue(NooraMock(terminal: Terminal(isInteractive: false))) {
            try await AlertController.$current.withValue(AlertController()) {
                try await function()
            }
        }
    }
}

extension Trait where Self == NooraTestingTrait {
    static var withMockedNoora: Self { Self() }
}

struct LoggerTestingTrait: TestTrait, SuiteTrait, TestScoping {
    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let logger = Logger(label: "dev.tuist.test")
        try await Logger.$current.withValue(logger) {
            try await function()
        }
    }
}

extension Trait where Self == LoggerTestingTrait {
    static func withMockedLogger() -> Self { Self() }
}

func ui() -> String {
    AlertController.current.print()
    let output = (Noora.current as? NooraMock)?.description ?? ""
    return output.replacingOccurrences(
        of: #"\[[0-9]+(?:\.[0-9]+)?s\]"#,
        with: "[0.0s]",
        options: .regularExpression
    )
}
