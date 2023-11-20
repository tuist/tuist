import Foundation
import TuistCore
import TuistSupport
import XcbeautifyLib

protocol Formatting {
    func format(_ line: String) -> String?
}

final class Formatter: Formatting {
    private let parser: Parser

    init() {
        parser = Parser(
            colored: Environment.shared.shouldOutputBeColoured,
            renderer: Self.renderer(),
            additionalLines: { nil }
        )
    }

    func format(_ line: String) -> String? {
        parser.parse(line: line)
    }

    private static func renderer() -> Renderer {
        if Environment.shared.isGitHubActions {
            return .gitHubActions
        } else {
            return .terminal
        }
    }
}
