import ServiceContextModule
import TuistSupport
import XcbeautifyLib

protocol Formatting {
    func format(_ line: String) -> String?
}

final class Formatter: Formatting {
    private let formatter: XCBeautifier

    init() {
        let environment = ServiceContext.current!.environment!
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
