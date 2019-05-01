import Basic
import Foundation

public class Scheme: Equatable {
    // MARK: - Attributes

    public let name: String
    public let shared: Bool
    public let buildAction: BuildAction?
    public let testAction: TestAction?
    public let runAction: RunAction?

    // MARK: - Init

    public init(name: String,
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

    public static func == (lhs: Scheme, rhs: Scheme) -> Bool {
        return lhs.name == rhs.name &&
            lhs.shared == rhs.shared &&
            lhs.buildAction == rhs.buildAction &&
            lhs.testAction == rhs.testAction &&
            lhs.runAction == rhs.runAction
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

public class SerialAction: Equatable {
    
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]
    
    // MARK: - Init
    
    public init(preActions: [ExecutionAction] = [],
         postActions: [ExecutionAction] = []) {
        self.preActions = preActions
        self.postActions = postActions
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: SerialAction, rhs: SerialAction) -> Bool {
        return lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}

public class BuildAction: SerialAction {
    // MARK: - Attributes

    public let targets: [String]

    // MARK: - Init

    public init(targets: [String] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        
        self.targets = targets
        super.init(preActions: preActions, postActions: postActions)
    }

    // MARK: - Equatable

    public static func == (lhs: BuildAction, rhs: BuildAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}

public class TestAction: SerialAction {
    // MARK: - Attributes

    public let targets: [String]
    public let arguments: Arguments?
    public let config: BuildConfiguration
    public let coverage: Bool

    // MARK: - Init

    public init(targets: [String] = [],
                arguments: Arguments? = nil,
                config: BuildConfiguration = .debug,
                coverage: Bool = false,
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.targets = targets
        self.arguments = arguments
        self.config = config
        self.coverage = coverage
        super.init(preActions: preActions, postActions: postActions)
    }

    // MARK: - Equatable

    public static func == (lhs: TestAction, rhs: TestAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.arguments == rhs.arguments &&
            lhs.config == rhs.config &&
            lhs.coverage == rhs.coverage &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}

public class RunAction: Equatable {
    // MARK: - Attributes

    public let config: BuildConfiguration
    public let executable: String?
    public let arguments: Arguments?

    // MARK: - Init

    public init(config: BuildConfiguration,
                executable: String? = nil,
                arguments: Arguments? = nil) {
        self.config = config
        self.executable = executable
        self.arguments = arguments
    }

    // MARK: - Equatable

    public static func == (lhs: RunAction, rhs: RunAction) -> Bool {
        return lhs.config == rhs.config &&
            lhs.executable == rhs.executable &&
            lhs.arguments == rhs.arguments
    }
}
