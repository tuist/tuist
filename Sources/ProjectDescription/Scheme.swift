import Foundation

// MARK: - Scheme

public struct Scheme: Equatable, Codable {
    public let name: String
    public let shared: Bool
    public let buildAction: BuildAction?
    public let testAction: TestAction?
    public let runAction: RunAction?
    public let archiveAction: ArchiveAction?

    public init(name: String,
                shared: Bool = true,
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
}

// MARK: - ExecutionAction

public struct ExecutionAction: Equatable, Codable {
    public let title: String
    public let scriptText: String
    public let target: String?

    public init(title: String = "Run Script", scriptText: String, target: String? = nil) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
    }
}

// MARK: - Arguments

public struct Arguments: Equatable, Codable {
    public let environment: [String: String]
    public let launch: [String: Bool]

    public init(environment: [String: String] = [:],
                launch: [String: Bool] = [:]) {
        self.environment = environment
        self.launch = launch
    }
}

// MARK: - BuildAction

public struct BuildAction: Equatable, Codable {
    public let targets: [String]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    public init(targets: [String],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
    }
}

// MARK: - TestAction

public struct TestAction: Equatable, Codable {
    public let targets: [TestableTarget]
    public let arguments: Arguments?
    public let configurationName: String
    public let coverage: Bool
    public let codeCoverageTargets: [String]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

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

    public init(targets: [TestableTarget],
                arguments: Arguments? = nil,
                config: PresetBuildConfiguration = .debug,
                coverage: Bool = false,
                codeCoverageTargets: [String] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.init(targets: targets,
                  arguments: arguments,
                  configurationName: config.name,
                  coverage: coverage,
                  codeCoverageTargets: codeCoverageTargets,
                  preActions: preActions,
                  postActions: postActions)
    }
}

public struct TestableTarget: Equatable, Hashable, Codable, ExpressibleByStringLiteral {
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

    public init(stringLiteral value: String) {
        self.init(target: value)
    }
}

// MARK: - RunAction

public struct RunAction: Equatable, Codable {
    public let configurationName: String
    public let executable: String?
    public let arguments: Arguments?

    public init(configurationName: String,
                executable: String? = nil,
                arguments: Arguments? = nil) {
        self.configurationName = configurationName
        self.executable = executable
        self.arguments = arguments
    }

    public init(config: PresetBuildConfiguration = .debug,
                executable: String? = nil,
                arguments: Arguments? = nil) {
        self.init(configurationName: config.name,
                  executable: executable,
                  arguments: arguments)
    }
}

// MARK: - Archive Action

public struct ArchiveAction: Equatable, Codable {
    public let configurationName: String
    public let revealArchiveInOrganizer: Bool
    public let customArchiveName: String?
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

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
}
