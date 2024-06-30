import Foundation
import TuistCore
import TuistSupport
import XcbeautifyLib

protocol Formatting {
    func format(_ line: String) -> String?
}

final class Formatter: Formatting {
    private let formatter: XCBeautifier

    init(environment: Environmenting = Environment.shared) {
        formatter = XCBeautifier(
            colored: environment.shouldOutputBeColoured,
            renderer: Self.renderer(for: environment),
            preserveUnbeautifiedLines: false,
            additionalLines: { nil }
        )
    }

    func format(_ line: String) -> String? {
        formatter.format(line: line)
    }

    private static func renderer(for environment: Environmenting) -> Renderer {
        if environment.isGitHubActions {
            return .gitHubActions
        } else {
            return .terminal
        }
    }
}
