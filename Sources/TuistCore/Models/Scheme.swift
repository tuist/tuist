import Basic
import Foundation

public class Scheme: Equatable {
    // MARK: - Attributes

    public let name: String
    public let shared: Bool
    public let buildAction: BuildAction?
    public let testAction: TestAction?
    public let runAction: RunAction?
    public let archiveAction: ArchiveAction?

    // MARK: - Init

    public init(name: String,
                shared: Bool = false,
                buildAction: BuildAction? = nil,
                testAction: TestAction? = nil,
                runAction: RunAction? = nil,
                archiveAction: ArchiveAction? = nil) {
        self.name = name
        self.shared = shared
        self.buildAction = buildAction
        self.testAction = testAction
        self.runAction = runAction
        self.archiveAction = archiveAction
    }

    public func targetDependencies() -> [TargetReference] {
        let targetSources: [[TargetReference]?] = [
            buildAction?.targets,
            buildAction?.preActions.compactMap(\.target),
            buildAction?.postActions.compactMap(\.target),
            testAction?.targets.map(\.target),
            testAction?.codeCoverageTargets,
            testAction?.preActions.compactMap(\.target),
            testAction?.postActions.compactMap(\.target),
            runAction?.executable.map { [$0] },
            archiveAction?.preActions.compactMap(\.target),
            archiveAction?.postActions.compactMap(\.target),
        ]

        let targets = targetSources.compactMap { $0 }.flatMap { $0 }.uniqued()
        return targets.sorted { ($0.name < $1.name) }
    }

    // MARK: - Equatable

    public static func == (lhs: Scheme, rhs: Scheme) -> Bool {
        lhs.name == rhs.name &&
            lhs.shared == rhs.shared &&
            lhs.buildAction == rhs.buildAction &&
            lhs.testAction == rhs.testAction &&
            lhs.runAction == rhs.runAction &&
            lhs.archiveAction == rhs.archiveAction
    }
}

public struct Arguments: Equatable {
    // MARK: - Attributes

    public let environment: [String: String]
    public let launch: [String: Bool]

    // MARK: - Init

    public init(environment: [String: String] = [:],
                launch: [String: Bool] = [:]) {
        self.environment = environment
        self.launch = launch
    }

    // MARK: - Equatable

    public static func == (lhs: Arguments, rhs: Arguments) -> Bool {
        lhs.environment == rhs.environment &&
            lhs.launch == rhs.launch
    }
}

public struct ExecutionAction: Equatable {
    // MARK: - Attributes

    public let title: String
    public let scriptText: String
    public let target: TargetReference?

    // MARK: - Init

    public init(title: String,
                scriptText: String,
                target: TargetReference?) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
    }

    public static func == (lhs: ExecutionAction, rhs: ExecutionAction) -> Bool {
        lhs.title == rhs.title &&
            lhs.scriptText == rhs.scriptText &&
            lhs.target == rhs.target
    }
}

public struct TargetReference: Hashable {
    public var projectPath: AbsolutePath
    public var name: String

    public static func project(path: AbsolutePath, target: String) -> TargetReference {
        .init(projectPath: path, name: target)
    }

    public init(projectPath: AbsolutePath, name: String) {
        self.projectPath = projectPath
        self.name = name
    }
}
