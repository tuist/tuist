import Foundation

// MARK: - Scheme

public struct Scheme: Equatable, Codable {
    public let name: String
    public let shared: Bool
    public let buildAction: BuildAction?
    public let testAction: TestAction?
    public let runAction: RunAction?

    public init(name: String,
                shared: Bool = true,
                buildAction: BuildAction? = nil,
                testAction: TestAction? = nil,
                runAction: RunAction? = nil) {
        self.name = name
        self.shared = shared
        self.buildAction = buildAction
        self.testAction = testAction
        self.runAction = runAction
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
    public let targets: [String]
    public let arguments: Arguments?
    public let configurationName: String
    public let coverage: Bool
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    public init(targets: [String],
                arguments: Arguments? = nil,
                configurationName: String,
                coverage: Bool = false,
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.targets = targets
        self.arguments = arguments
        self.configurationName = configurationName
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
    }

    public init(targets: [String],
                arguments: Arguments? = nil,
                config: PresetBuildConfiguration = .debug,
                coverage: Bool = false,
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.init(targets: targets,
                  arguments: arguments,
                  configurationName: config.name,
                  coverage: coverage,
                  preActions: preActions,
                  postActions: postActions)
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
