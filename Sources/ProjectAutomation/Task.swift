import Foundation

public struct Task {
    public let options: [Option]
    public let task: ([String: String], Graph) throws -> Void

    public enum Option: Equatable {
        case option(String)
    }

    public init(
        options: [Option] = [],
        task: @escaping ([String: String], Graph) throws -> Void
    ) {
        self.options = options
        self.task = task

        runIfNeeded()
    }

    private func runIfNeeded() {
        guard
            let taskCommandLineIndex = CommandLine.arguments.firstIndex(of: "--tuist-task"),
            CommandLine.argc > taskCommandLineIndex
        else { return }
        let attributesString = CommandLine.arguments[taskCommandLineIndex + 1]
        let decoder = JSONDecoder()
        // swiftlint:disable force_try
        let attributes = try! decoder.decode(
            [String: String].self,
            from: attributesString.data(using: .utf8)!
        )
        let graph = try! decoder.decode(
            Graph.self,
            from: CommandLine.arguments[taskCommandLineIndex + 2].data(using: .utf8)!
        )
        try! task(attributes, graph)
        // swiftlint:enable force_try
    }
}
