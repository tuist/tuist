import Foundation

public struct Task {
    public let options: [Option]
    public let task: ([String: String]) throws -> Void

    public enum Option: Equatable {
        case option(String)
    }

    public init(
        options: [Option] = [],
        task: @escaping ([String: String]) throws -> Void
    ) {
        self.options = options
        self.task = task

        runIfNeeded()
    }

    private func runIfNeeded() {
        guard let taskCommandLineIndex = CommandLine.arguments.firstIndex(of: "--tuist-task"),
              CommandLine.argc > taskCommandLineIndex
        else { return }
        let attributesString = CommandLine.arguments[taskCommandLineIndex + 1]
        // swiftlint:disable force_try
        let attributes: [String: String] = try! JSONDecoder().decode(
            [String: String].self,
            from: attributesString.data(using: .utf8)!
        )
        try! task(attributes)
        // swiftlint:enable force_try
    }
}
