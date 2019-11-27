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

    // MARK: - Equatable

    public static func == (lhs: Scheme, rhs: Scheme) -> Bool {
        return lhs.name == rhs.name &&
            lhs.shared == rhs.shared &&
            lhs.buildAction == rhs.buildAction &&
            lhs.testAction == rhs.testAction &&
            lhs.runAction == rhs.runAction &&
            lhs.archiveAction == rhs.archiveAction
    }
}

public class Arguments: Equatable {
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
        return lhs.environment == rhs.environment &&
            lhs.launch == rhs.launch
    }
}

public class ExecutionAction: Equatable {
    // MARK: - Attributes

    public let title: String
    public let scriptText: String
    public let target: String?

    // MARK: - Init

    public init(title: String,
                scriptText: String,
                target: String?) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
    }

    public static func == (lhs: ExecutionAction, rhs: ExecutionAction) -> Bool {
        return lhs.title == rhs.title &&
            lhs.scriptText == rhs.scriptText &&
            lhs.target == rhs.target
    }
}

public class BuildAction: Equatable {
    // MARK: - Attributes

    public let targets: [String]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    // MARK: - Init

    public init(targets: [String] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
    }

    // MARK: - Equatable

    public static func == (lhs: BuildAction, rhs: BuildAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}

public class TestAction: Equatable {
    // MARK: - Attributes

    public let targets: [TestableTarget]
    public let arguments: Arguments?
    public let configurationName: String
    public let coverage: Bool
    public let codeCoverageTargets: [String]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    // MARK: - Init

    public init(targets: [TestableTarget] = [],
                arguments: Arguments? = nil,
                configurationName: String,
                coverage: Bool = false,
                codeCoverageTargets: [String] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.targets = targets
        self.arguments = arguments
        self.configurationName = configurationName
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
        self.codeCoverageTargets = codeCoverageTargets
    }

    // MARK: - Equatable

    public static func == (lhs: TestAction, rhs: TestAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.arguments == rhs.arguments &&
            lhs.configurationName == rhs.configurationName &&
            lhs.coverage == rhs.coverage &&
            lhs.codeCoverageTargets == rhs.codeCoverageTargets &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}

public struct TestableTarget: Equatable, Hashable {
    public let target: String
    public let isSkipped: Bool
    public let isParallelizable: Bool
    public let isRandomExecutionOrdering: Bool

    public init(target: String, skipped: Bool = false, parallelizable: Bool = false, randomExecutionOrdering: Bool = false) {
        self.target = target
        self.isSkipped = skipped
        self.isParallelizable = parallelizable
        self.isRandomExecutionOrdering = randomExecutionOrdering
    }
}

public class RunAction: Equatable {
    // MARK: - Attributes

    public let configurationName: String
    public let executable: String?
    public let arguments: Arguments?

    // MARK: - Init

    public init(configurationName: String,
                executable: String? = nil,
                arguments: Arguments? = nil) {
        self.configurationName = configurationName
        self.executable = executable
        self.arguments = arguments
    }

    // MARK: - Equatable

    public static func == (lhs: RunAction, rhs: RunAction) -> Bool {
        return lhs.configurationName == rhs.configurationName &&
            lhs.executable == rhs.executable &&
            lhs.arguments == rhs.arguments
    }
}

public class ArchiveAction: Equatable {
    // MARK: - Attributes

    public let configurationName: String
    public let revealArchiveInOrganizer: Bool
    public let customArchiveName: String?
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    // MARK: - Init

    public init(
        configurationName: String,
        revealArchiveInOrganizer: Bool = true,
        customArchiveName: String? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) {
        self.configurationName = configurationName
        self.revealArchiveInOrganizer = revealArchiveInOrganizer
        self.customArchiveName = customArchiveName
        self.preActions = preActions
        self.postActions = postActions
    }

    // MARK: - Equatable

    public static func == (lhs: ArchiveAction, rhs: ArchiveAction) -> Bool {
        return lhs.configurationName == rhs.configurationName
            && lhs.revealArchiveInOrganizer == rhs.revealArchiveInOrganizer
            && lhs.customArchiveName == rhs.customArchiveName
            && lhs.preActions == rhs.preActions
            && lhs.postActions == rhs.postActions
    }
}
