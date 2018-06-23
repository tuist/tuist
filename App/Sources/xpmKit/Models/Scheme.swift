import Basic
import Foundation

/// Xcode project scheme.
class Scheme: JSONMappable, Equatable {
    /// Scheme name.
    let name: String

    /// True if the scheme is shared.
    let shared: Bool

    /// Scheme build action.
    let buildAction: BuildAction?

    /// Scheme test action.
    let testAction: TestAction?

    /// Scheme run action.
    let runAction: RunAction?

    /// Initializes the scheme with its properties.
    ///
    /// - Parameters:
    ///   - name: scheme name.
    ///   - shared: whether the scheme is shared or not.
    ///   - buildAction: build action.
    ///   - testAction: test action.
    ///   - runAction: run action.
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

    /// Initializes the scheme with its JSON representation.
    ///
    /// - Parameter json: JSON representation.
    /// - Throws: an error if it cannot be parsed.
    required init(json: JSON) throws {
        name = try json.get("name")
        shared = try json.get("shared")
        buildAction = try? json.get("build_action")
        testAction = try? json.get("test_action")
        runAction = try? json.get("run_action")
    }

    /// Compares two schemes.
    ///
    /// - Parameters:
    ///   - lhs: first scheme to be compared.
    ///   - rhs: second scheme to be compared.
    /// - Returns: true if the two schemes are the same.
    static func == (lhs: Scheme, rhs: Scheme) -> Bool {
        return lhs.name == rhs.name &&
            lhs.shared == rhs.shared &&
            lhs.buildAction == rhs.buildAction &&
            lhs.testAction == rhs.testAction &&
            lhs.runAction == rhs.runAction
    }
}

/// Scheme action arguments.
class Arguments: JSONMappable, Equatable {
    /// Environment variables.
    let environment: [String: String]

    /// Launch arguments. The key represents the argument, and the value whether the argument is enabled or not.
    let launch: [String: Bool]

    /// Initializes the arguments with its properties.
    ///
    /// - Parameters:
    ///   - environment: environment variables.
    ///   - launch: launch arguments.
    init(environment: [String: String] = [:],
         launch: [String: Bool] = [:]) {
        self.environment = environment
        self.launch = launch
    }

    /// Initializes Arguments with its JSON representation.
    ///
    /// - Parameter json: JSON representation.
    /// - Throws: an error if the arguments cannot be parsed.
    required init(json: JSON) throws {
        environment = try json.get("environment")
        launch = try json.get("launch")
    }

    /// Compares two Argument instances.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two arguments are the same.
    static func == (lhs: Arguments, rhs: Arguments) -> Bool {
        return lhs.environment == rhs.environment &&
            lhs.launch == rhs.launch
    }
}

/// Scheme build action.
class BuildAction: JSONMappable, Equatable {
    /// Build action targets.
    let targets: [String]

    /// Initializes the build action with its properties.
    ///
    /// - Parameter targets: targets to be built.
    init(targets: [String] = []) {
        self.targets = targets
    }

    /// Initializes BuildAction with its JSON representation.
    ///
    /// - Parameter json: JSON representation.
    /// - Throws: an error if the action cannot be parsed.
    required init(json: JSON) throws {
        targets = try json.get("targets")
    }

    /// Compares two build action instances.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: BuildAction, rhs: BuildAction) -> Bool {
        return lhs.targets == rhs.targets
    }
}

/// Test action.
class TestAction: JSONMappable, Equatable {
    /// Targets that are tested.
    let targets: [String]

    /// Arguments.
    let arguments: Arguments?

    /// Build configuration.
    let config: BuildConfiguration

    /// True if the test coverage data should be gathered.
    let coverage: Bool

    /// Initializes the test action with its attributes.
    ///
    /// - Parameters:
    ///   - targets: targets to be tested.
    ///   - arguments: launch arguments.
    ///   - config: build configuration.
    ///   - coverage: whether the test coverage should be gathered.
    init(targets: [String] = [],
         arguments: Arguments? = nil,
         config: BuildConfiguration = .debug,
         coverage: Bool = false) {
        self.targets = targets
        self.arguments = arguments
        self.config = config
        self.coverage = coverage
    }

    /// Initializes the test action with its JSON representation.
    ///
    /// - Parameter json: JSON representation.
    /// - Throws: an error if the action cannot be parsed.
    required init(json: JSON) throws {
        targets = try json.get("targets")
        arguments = try? json.get("arguments")
        let configString: String = try json.get("config")
        config = BuildConfiguration(rawValue: configString)!
        coverage = try json.get("coverage")
    }

    /// Compares two test actions.
    ///
    /// - Parameters:
    ///   - lhs: first test action to be compared.
    ///   - rhs: second test action to be compared.
    /// - Returns: true if the two actions are the same.
    static func == (lhs: TestAction, rhs: TestAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.arguments == rhs.arguments &&
            lhs.config == rhs.config &&
            lhs.coverage == rhs.coverage
    }
}

/// Run action
class RunAction: JSONMappable, Equatable {
    /// Build configuration to be run.
    let config: BuildConfiguration

    /// Name of the executable.
    let executable: String?

    /// Run action arguments.
    let arguments: Arguments?

    /// Initializes the run action with its attributes.
    ///
    /// - Parameters:
    ///   - config: build configuration.
    ///   - executable: executable.
    ///   - arguments: launch arguments.
    init(config: BuildConfiguration,
         executable: String? = nil,
         arguments: Arguments? = nil) {
        self.config = config
        self.executable = executable
        self.arguments = arguments
    }

    /// Initializes the run action with its JSON representation.
    ///
    /// - Parameter json: JSON representation.
    /// - Throws: throws an error if it cannot be parsed.
    required init(json: JSON) throws {
        let configString: String = try json.get("config")
        config = BuildConfiguration(rawValue: configString)!
        executable = try? json.get("executable")
        arguments = try? json.get("arguments")
    }

    static func == (lhs: RunAction, rhs: RunAction) -> Bool {
        return lhs.config == rhs.config &&
            lhs.executable == rhs.executable &&
            lhs.arguments == rhs.arguments
    }
}
