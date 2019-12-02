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
        return lhs.title == rhs.title &&
            lhs.scriptText == rhs.scriptText &&
            lhs.target == rhs.target
    }
}

public class TargetReference: Equatable {
    public var projectPath: AbsolutePath
    public var name: String

    public static func project(path: AbsolutePath, target: String) -> TargetReference {
        return .init(projectPath: path, name: target)
    }
    
    public init(projectPath: AbsolutePath, name: String) {
        self.projectPath = projectPath
        self.name = name
    }
    
    public static func == (lhs: TargetReference, rhs: TargetReference) -> Bool {
        return lhs.projectPath == rhs.projectPath &&
            lhs.name == rhs.name
    }
}

public class BuildAction: Equatable {
    // MARK: - Attributes

    public let targets: [TargetReference]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    // MARK: - Init

    public init(targets: [TargetReference] = [],
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
    public let codeCoverageTargets: [TargetReference]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    // MARK: - Init

    public init(targets: [TestableTarget] = [],
                arguments: Arguments? = nil,
                configurationName: String,
                coverage: Bool = false,
                codeCoverageTargets: [TargetReference] = [],
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

public struct TestableTarget: Equatable {
    public let target: TargetReference
    public let isSkipped: Bool
    public let isParallelizable: Bool
    public let isRandomExecutionOrdering: Bool

    public init(target: TargetReference, skipped: Bool = false, parallelizable: Bool = false, randomExecutionOrdering: Bool = false) {
        self.target = target
        self.isSkipped = skipped
        self.isParallelizable = parallelizable
        self.isRandomExecutionOrdering = randomExecutionOrdering
    }
}

public class RunAction: Equatable {
    // MARK: - Attributes

    public let configurationName: String
    public let executable: TargetReference?
    public let arguments: Arguments?

    // MARK: - Init

    public init(configurationName: String,
                executable: TargetReference? = nil,
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
