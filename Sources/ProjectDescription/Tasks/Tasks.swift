import Foundation

//public struct Tasks: Codable, ExpressibleByArrayLiteral {
//    public let tasks: [String: Task]
//
//    public init(arrayLiteral elements: Task...) {
//        self.init(elements)
//    }
//
//    public init(
//        _ tasks: [Task]
//    ) {
//        self.tasks = tasks.reduce(into: [:]) { acc, task in
//            acc[task.name] = task
//        }
//        if !dumpIfNeeded(self) {
//            runIfNeeded()
//        }
//    }
//
//    private func runIfNeeded() {
//        guard
//            let taskCommandLineIndex = CommandLine.arguments.firstIndex(of: "--tuist-task"),
//            CommandLine.argc > taskCommandLineIndex
//        else { return }
//        let name = CommandLine.arguments[taskCommandLineIndex + 1]
//        let attributesString = CommandLine.arguments[taskCommandLineIndex + 2]
//        // swiftlint:disable force_try
//        let attributes: [String: String] = try! JSONDecoder().decode(
//            [String: String].self,
//            from: attributesString.data(using: .utf8)!
//        )
//        try! tasks[name]!.task(attributes)
//        // swiftlint:enable force_try
//    }
//}
