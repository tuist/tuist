import Foundation

// MARK: - Scheme

public class Scheme: Codable {
    public let name: String
    public let shared: Bool
    public let buildAction: BuildAction?
    public let testAction: TestAction?
    public let runAction: RunAction?

    public enum CodingKeys: String, CodingKey {
        case name
        case shared
        case buildAction = "build_action"
        case testAction = "test_action"
        case runAction = "run_action"
    }

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

public class ExecutionAction: Codable {
    
    public let title: String
    public let scriptText: String
    public let target: String?
    
    public enum CodingKeys: String, CodingKey {
        case title
        case scriptText = "script_text"
        case target
    }
    
    public init(title: String = "Run Script", scriptText: String, target: String? = nil) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
    }
}

// MARK: - Arguments

public class Arguments: Codable {
    public let environment: [String: String]
    public let launch: [String: Bool]

    public enum CodingKeys: String, CodingKey {
        case environment
        case launch
    }

    public init(environment: [String: String] = [:],
                launch: [String: Bool] = [:]) {
        self.environment = environment
        self.launch = launch
    }
}

// MARK: - BuildAction

public class BuildAction: Codable {
    public let targets: [String]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    public enum CodingKeys: String, CodingKey {
        case targets
        case preActions = "pre_actions"
        case postActions = "post_actions"
    }
    
    public init(targets: [String],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
    }
}

// MARK: - TestAction

public class TestAction: Codable {
    public let targets: [String]
    public let arguments: Arguments?
    public let config: BuildConfiguration
    public let coverage: Bool
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    public enum CodingKeys: String, CodingKey {
        case targets
        case arguments
        case config
        case coverage
        case preActions = "pre_actions"
        case postActions = "post_actions"
    }

    public init(targets: [String],
                arguments: Arguments? = nil,
                config: BuildConfiguration = .debug,
                coverage: Bool = false,
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []){
        self.targets = targets
        self.arguments = arguments
        self.config = config
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
    }
}

// MARK: - RunAction

public class RunAction: Codable {
    public let config: BuildConfiguration
    public let executable: String?
    public let arguments: Arguments?

    public enum CodingKeys: String, CodingKey {
        case config
        case executable
        case arguments
    }

    public init(config: BuildConfiguration = .debug,
                executable: String? = nil,
                arguments: Arguments? = nil) {
        self.config = config
        self.executable = executable
        self.arguments = arguments
    }
}
