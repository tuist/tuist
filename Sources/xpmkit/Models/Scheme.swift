import Basic
import Foundation

class Scheme: JSONMappable, Equatable {

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

    required init(json: JSON) throws {
        name = try json.get("name")
        shared = try json.get("shared")
        buildAction = try? json.get("build_action")
        testAction = try? json.get("test_action")
        runAction = try? json.get("run_action")
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

class Arguments: JSONMappable, Equatable {

    // MARK: - Attributes

    let environment: [String: String]
    let launch: [String: Bool]

    // MARK: - Init

    init(environment: [String: String] = [:],
         launch: [String: Bool] = [:]) {
        self.environment = environment
        self.launch = launch
    }

    required init(json: JSON) throws {
        environment = try json.get("environment")
        launch = try json.get("launch")
    }

    // MARK: - Equatable

    static func == (lhs: Arguments, rhs: Arguments) -> Bool {
        return lhs.environment == rhs.environment &&
            lhs.launch == rhs.launch
    }
}

class BuildAction: JSONMappable, Equatable {

    // MARK: - Attributes

    let targets: [String]

    // MARK: - Init

    init(targets: [String] = []) {
        self.targets = targets
    }

    required init(json: JSON) throws {
        targets = try json.get("targets")
    }

    // MARK: - Equatable

    static func == (lhs: BuildAction, rhs: BuildAction) -> Bool {
        return lhs.targets == rhs.targets
    }
}

class TestAction: JSONMappable, Equatable {

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

    required init(json: JSON) throws {
        targets = try json.get("targets")
        arguments = try? json.get("arguments")
        let configString: String = try json.get("config")
        config = BuildConfiguration(rawValue: configString)!
        coverage = try json.get("coverage")
    }

    // MARK: - Equatable

    static func == (lhs: TestAction, rhs: TestAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.arguments == rhs.arguments &&
            lhs.config == rhs.config &&
            lhs.coverage == rhs.coverage
    }
}

class RunAction: JSONMappable, Equatable {

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

    required init(json: JSON) throws {
        let configString: String = try json.get("config")
        config = BuildConfiguration(rawValue: configString)!
        executable = try? json.get("executable")
        arguments = try? json.get("arguments")
    }

    // MARK: - Equatable

    static func == (lhs: RunAction, rhs: RunAction) -> Bool {
        return lhs.config == rhs.config &&
            lhs.executable == rhs.executable &&
            lhs.arguments == rhs.arguments
    }
}
