import Foundation

// MARK: - Scheme

public class Scheme {
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

// MARK: - Scheme (JSONConvertible)

extension Scheme: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["name"] = name.toJSON()
        dictionary["shared"] = shared.toJSON()
        if let buildAction = buildAction {
            dictionary["build_action"] = buildAction.toJSON()
        }
        if let testAction = testAction {
            dictionary["test_action"] = testAction.toJSON()
        }
        if let runAction = runAction {
            dictionary["run_action"] = runAction.toJSON()
        }
        return .dictionary(dictionary)
    }
}

// MARK: - Arguments

public class Arguments {
    public let environment: [String: String]
    public let launch: [String: Bool]
    public init(environment: [String: String],
                launch: [String: Bool]) {
        self.environment = environment
        self.launch = launch
    }
}

// MARK: - Arguments (JSONConvertible)

extension Arguments: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["environment"] = environment.toJSON()
        dictionary["launch"] = launch.toJSON()
        return .dictionary(dictionary)
    }
}

// MARK: - BuildAction

public class BuildAction {
    public let targets: [String]
    public init(targets: [String]) {
        self.targets = targets
    }
}

// MARK: - BuildAction (JSONConvertible)

extension BuildAction: JSONConvertible {
    func toJSON() -> JSON {
        return .dictionary(["targets": targets.toJSON()])
    }
}

// MARK: - TestAction

public class TestAction {
    public let targets: [String]
    public let arguments: Arguments?
    public let config: BuildConfiguration
    public let coverage: Bool
    public init(targets: [String],
                arguments: Arguments? = nil,
                config: BuildConfiguration = .debug,
                coverage: Bool = false) {
        self.targets = targets
        self.arguments = arguments
        self.config = config
        self.coverage = coverage
    }
}

// MARK: - TestAction (JSONConvertible)

extension TestAction: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["targets"] = targets.toJSON()
        if let arguments = arguments {
            dictionary["arguments"] = arguments.toJSON()
        }
        dictionary["config"] = config.toJSON()
        dictionary["coverage"] = coverage.toJSON()
        return .dictionary(dictionary)
    }
}

// MARK: - RunAction

public class RunAction {
    public let config: BuildConfiguration
    public let executable: String?
    public let arguments: Arguments?
    public init(config: BuildConfiguration = .debug,
                executable: String? = nil,
                arguments: Arguments? = nil) {
        self.config = config
        self.executable = executable
        self.arguments = arguments
    }
}

// MARK: - RunAction (JSONConvertible)

extension RunAction: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        if let executable = executable {
            dictionary["executable"] = executable.toJSON()
        }
        if let arguments = arguments {
            dictionary["arguments"] = arguments.toJSON()
        }
        dictionary["config"] = config.toJSON()
        return .dictionary(dictionary)
    }
}
