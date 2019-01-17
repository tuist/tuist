import Basic
import Foundation

class Scheme: JSONMappable, Equatable {
    // MARK: - Attributes

    let name: String
    let shared: Bool
    let buildAction: BuildAction?
    let testAction: TestAction?
    let runAction: RunAction?
    let archiveAction: ArchiveAction?
    
    // MARK: - Init

    init(name: String,
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

    required init(json: JSON) throws {
        name = try json.get("name")
        shared = try json.get("shared")
        buildAction = try? json.get("build_action")
        testAction = try? json.get("test_action")
        runAction = try? json.get("run_action")
        archiveAction = try? json.get("archive_action")
    }

    // MARK: - Equatable

    static func == (lhs: Scheme, rhs: Scheme) -> Bool {
        return lhs.name == rhs.name &&
            lhs.shared == rhs.shared &&
            lhs.buildAction == rhs.buildAction &&
            lhs.testAction == rhs.testAction &&
            lhs.runAction == rhs.runAction &&
            lhs.archiveAction == rhs.archiveAction
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

class ExecutionAction: JSONMappable, Equatable {
   
    // MARK: - Attributes
    
    let title: String
    let scriptText: String
    let target: String?
    
    // MARK: - Init
    
    init(title: String,
         scriptText: String,
         target: String?) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
    }
    
    required init(json: JSON) throws {
        self.title = try json.get("title")
        self.scriptText = try json.get("scriptText")
        self.target = try? json.get("target")
    }
    
    static func == (lhs: ExecutionAction, rhs: ExecutionAction) -> Bool {
        return lhs.title == rhs.title &&
            lhs.scriptText == rhs.scriptText &&
            lhs.target == rhs.target
    }
}

class SerialAction: JSONMappable, Equatable {
    
    let preActions: [ExecutionAction]
    let postActions: [ExecutionAction]
    
    // MARK: - Init

    init(preActions: [ExecutionAction] = [],
         postActions: [ExecutionAction] = []) {
        self.preActions = preActions
        self.postActions = postActions
    }
    
    required init(json: JSON) throws {
        preActions = try json.get("pre_actions")
        postActions = try json.get("post_actions")
    }
    
    // MARK: - Equatable
    
    static func == (lhs: SerialAction, rhs: SerialAction) -> Bool {
        return lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }

}
class BuildAction: SerialAction {
    // MARK: - Attributes

    let targets: [String]

    // MARK: - Init

    init(targets: [String],
         preActions: [ExecutionAction] = [],
         postActions: [ExecutionAction] = []) {
        self.targets = targets
        super.init(preActions: preActions, postActions: postActions)
    }

    required init(json: JSON) throws {
        targets = try json.get("targets")
        try super.init(json: json)
    }

    // MARK: - Equatable

    static func == (lhs: BuildAction, rhs: BuildAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}

class TestAction: SerialAction {
    // MARK: - Attributes

    let targets: [String]
    let arguments: Arguments?
    let config: BuildConfiguration
    let coverage: Bool
    

    // MARK: - Init

    init(targets: [String] = [],
         preActions: [ExecutionAction] = [],
         postActions: [ExecutionAction] = [],
         arguments: Arguments? = nil,
         config: BuildConfiguration = .debug,
         coverage: Bool = false) {
        self.targets = targets
        self.arguments = arguments
        self.config = config
        self.coverage = coverage
        super.init(preActions: preActions, postActions: postActions)
    }

    required init(json: JSON) throws {
        targets = try json.get("targets")
        arguments = try? json.get("arguments")
        let configString: String = try json.get("config")
        config = BuildConfiguration(rawValue: configString)!
        coverage = try json.get("coverage")
        try super.init(json: json)
    }

    // MARK: - Equatable

    static func == (lhs: TestAction, rhs: TestAction) -> Bool {
        return lhs.targets == rhs.targets &&
            lhs.arguments == rhs.arguments &&
            lhs.config == rhs.config &&
            lhs.coverage == rhs.coverage &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
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

class ArchiveAction: SerialAction {
    
    let config: BuildConfiguration

    // MARK: - Init
    
    init(config: BuildConfiguration,
         preActions: [ExecutionAction] = [],
         postActions: [ExecutionAction] = []) {
        self.config = config
        super.init(preActions: preActions, postActions: postActions)
    }
    
    required init(json: JSON) throws {
        let configString: String = try json.get("config")
        config = BuildConfiguration(rawValue: configString)!
        try super.init(json: json)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ArchiveAction, rhs: ArchiveAction) -> Bool {
        return lhs.config == rhs.config &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}

