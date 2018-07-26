import Foundation

// MARK: - Scheme

public class Scheme: Codable {
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

// MARK: - Arguments

public class Arguments: Codable {
    public let environment: [String: String]
    public let launch: [String: Bool]
    public init(environment: [String: String],
                launch: [String: Bool]) {
        self.environment = environment
        self.launch = launch
    }
}

// MARK: - BuildAction

public class BuildAction: Codable {
    public let targets: [String]
    public init(targets: [String]) {
        self.targets = targets
    }
}

// MARK: - TestAction

public class TestAction: Codable {
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

// MARK: - RunAction

public class RunAction: Codable {
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
