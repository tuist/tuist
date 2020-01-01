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
    public let target: TargetReference?

    public init(title: String = "Run Script", scriptText: String, target: TargetReference? = nil) {
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

// MARK: - RunAction

public struct RunAction: Equatable, Codable {
    public let configurationName: String
    public let executable: TargetReference?
    public let arguments: Arguments?

    public init(configurationName: String,
                executable: TargetReference? = nil,
                arguments: Arguments? = nil) {
        self.configurationName = configurationName
        self.executable = executable
        self.arguments = arguments
    }

    public init(config: PresetBuildConfiguration = .debug,
                executable: TargetReference? = nil,
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

// MARK: - Target Reference

public struct TargetReference: Equatable, Codable, ExpressibleByStringLiteral {
    public var projectPath: Path?
    public var targetName: String

    public init(projectPath: Path?, target: String) {
        self.projectPath = projectPath
        targetName = target
    }

    public init(stringLiteral value: String) {
        self = .init(projectPath: nil, target: value)
    }

    public static func project(path: Path, target: String) -> TargetReference {
        .init(projectPath: path, target: target)
    }
}
