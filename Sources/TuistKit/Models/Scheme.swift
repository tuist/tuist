import Basic
import Foundation

class Scheme: Equatable {
    // MARK: - Attributes

    let name: String
    let shared: Bool
    let buildAction: BuildAction?
    let testAction: TestAction?
    let runAction: RunAction?

    // MARK: - Init

    init(name: String,
         shared: Bool = false,
         buildAction: BuildAction? = nil,
         testAction: TestAction? = nil,
         runAction: RunAction? = nil) {
        self.name = name
        self.shared = shared
        self.buildAction = buildAction
        self.testAction = testAction
        self.runAction = runAction
    }

    // MARK: - Equatable

    static func == (lhs: Scheme, rhs: Scheme) -> Bool {
        return lhs.name == rhs.name &&
            lhs.shared == rhs.shared &&
            lhs.buildAction == rhs.buildAction &&
            lhs.testAction == rhs.testAction &&
            lhs.runAction == rhs.runAction
    }
}

class Arguments: Equatable {
    // MARK: - Attributes

    let environment: [String: String]
    let launch: [String: Bool]

    // MARK: - Init

    init(environment: [String: String] = [:],
         launch: [String: Bool] = [:]) {
        self.environment = environment
        self.launch = launch
    }

    // MARK: - Equatable

    static func == (lhs: Arguments, rhs: Arguments) -> Bool {
        return lhs.environment == rhs.environment &&
            lhs.launch == rhs.launch
    }
}

class BuildAction: Equatable {
    // MARK: - Attributes

    let targets: [String]

    // MARK: - Init

    init(targets: [String] = []) {
        self.targets = targets
    }

    // MARK: - Equatable

    static func == (lhs: BuildAction, rhs: BuildAction) -> Bool {
        return lhs.targets == rhs.targets
    }
}

class TestAction: Equatable {
    // MARK: - Attributes

    let targets: [String]
    let arguments: Arguments?
    let config: BuildConfiguration
    let coverage: Bool

    // MARK: - Init

    init(targets: [String] = [],
         arguments: Arguments? = nil,
         config: BuildConfiguration = .debug,
         coverage: Bool = false) {
        self.targets = targets
        self.arguments = arguments
        self.config = config
        self.coverage = coverage
    }

    // MARK: - Equatable

    static func == (lhs: TestAction, rhs: TestAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.arguments == rhs.arguments &&
            lhs.config == rhs.config &&
            lhs.coverage == rhs.coverage
    }
}

class RunAction: Equatable {
    // MARK: - Attributes

    let config: BuildConfiguration
    let executable: String?
    let arguments: Arguments?

    // MARK: - Init

    init(config: BuildConfiguration,
         executable: String? = nil,
         arguments: Arguments? = nil) {
        self.config = config
        self.executable = executable
        self.arguments = arguments
    }

    // MARK: - Equatable

    static func == (lhs: RunAction, rhs: RunAction) -> Bool {
        return lhs.config == rhs.config &&
            lhs.executable == rhs.executable &&
            lhs.arguments == rhs.arguments
    }
}
