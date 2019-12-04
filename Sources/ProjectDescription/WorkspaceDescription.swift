import Foundation

// MARK: - Scheme
public struct WorkspaceScheme: Equatable, Codable {
    public let name: String
    public let shared: Bool
    public let buildAction: WorkspaceDescription.BuildAction?
    public let testAction: WorkspaceDescription.TestAction?
    public let runAction: WorkspaceDescription.RunAction?
    public let archiveAction: WorkspaceDescription.ArchiveAction?

    public init(name: String,
                shared: Bool = true,
                buildAction: WorkspaceDescription.BuildAction? = nil,
                testAction: WorkspaceDescription.TestAction? = nil,
                runAction: WorkspaceDescription.RunAction? = nil,
                archiveAction: WorkspaceDescription.ArchiveAction? = nil) {
        self.name = name
        self.shared = shared
        self.buildAction = buildAction
        self.testAction = testAction
        self.runAction = runAction
        self.archiveAction = archiveAction
    }
}

public struct WorkspaceDescription {
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

    // MARK: - BuildActionTargets
    
    public struct TargetReference: Equatable, Codable {
        public var projectPath: String
        public var targetName: String
        
        public static func project(path: String, target: String) -> TargetReference {
            return .init(projectPath: path, targetName: target)
        }
    }

    // MARK: - BuildAction

    public struct BuildAction: Equatable, Codable {
        public let targets: [TargetReference]
        public let preActions: [ExecutionAction]
        public let postActions: [ExecutionAction]

        public init(targets: [TargetReference],
                    preActions: [ExecutionAction] = [],
                    postActions: [ExecutionAction] = []) {
            self.targets = targets
            self.preActions = preActions
            self.postActions = postActions
        }
        
        public static func buildAction(targets: [TargetReference],
                                       preActions: [ExecutionAction] = [],
                                       postActions: [ExecutionAction] = []) -> BuildAction {
            return .init(targets: targets,
                         preActions: preActions,
                         postActions: postActions)
        }
    }

    // MARK: - TestAction

    public struct TestAction: Equatable, Codable {
        public let targets: [TestableTarget]
        public let arguments: Arguments?
        public let configurationName: String
        public let coverage: Bool
        public let codeCoverageTargets: [String]
        public let preActions: [ExecutionAction]
        public let postActions: [ExecutionAction]

        public init(targets: [TestableTarget],
                    arguments: Arguments? = nil,
                    configurationName: String,
                    coverage: Bool = false,
                    codeCoverageTargets: [String] = [],
                    preActions: [ExecutionAction] = [],
                    postActions: [ExecutionAction] = []) {
            self.targets = targets
            self.arguments = arguments
            self.configurationName = configurationName
            self.coverage = coverage
            self.preActions = preActions
            self.postActions = postActions
            self.codeCoverageTargets = codeCoverageTargets
        }

        public init(targets: [TestableTarget],
                    arguments: Arguments? = nil,
                    config: PresetBuildConfiguration = .debug,
                    coverage: Bool = false,
                    codeCoverageTargets: [String] = [],
                    preActions: [ExecutionAction] = [],
                    postActions: [ExecutionAction] = []) {
            self.init(targets: targets,
                      arguments: arguments,
                      configurationName: config.name,
                      coverage: coverage,
                      codeCoverageTargets: codeCoverageTargets,
                      preActions: preActions,
                      postActions: postActions)
        }
        
        public static func testAction(targets: [TestableTarget],
                                      arguments: Arguments? = nil,
                                      config: PresetBuildConfiguration = .debug,
                                      coverage: Bool = false,
                                      codeCoverageTargets: [String] = [],
                                      preActions: [ExecutionAction] = [],
                                      postActions: [ExecutionAction] = []) -> TestAction {
            return .init(targets: targets,
                         arguments: arguments,
                         configurationName: config.name,
                         coverage: coverage,
                         codeCoverageTargets: codeCoverageTargets,
                         preActions: preActions,
                         postActions: postActions)
        }
    }
    
    public struct TestableTarget: Equatable, Codable {
        public let target: TargetReference
        public let isSkipped: Bool
        public let isParallelizable: Bool
        public let isRandomExecutionOrdering: Bool

        public init(target: TargetReference, skipped: Bool = false, parallelizable: Bool = false, randomExecutionOrdering: Bool = false) {
            self.target = target
            self.isSkipped = skipped
            self.isParallelizable = parallelizable
            self.isRandomExecutionOrdering = randomExecutionOrdering
        }
        
        public static func testableTarget(target: TargetReference, skipped: Bool = false, parallelizable: Bool = false, randomExecutionOrdering: Bool = false) -> TestableTarget {
            return .init(target: target, skipped: skipped, parallelizable: parallelizable, randomExecutionOrdering: randomExecutionOrdering)
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
        
        public static func runAction(configurationName: PresetBuildConfiguration = .debug,
                                     executable: TargetReference? = nil,
                                     arguments: Arguments? = nil) -> RunAction {
            return .init(config: configurationName,
                         executable: executable,
                         arguments: arguments)
        }
    }
    
    // MARK: - ArchiveAction
    
    public struct ArchiveAction: Equatable, Codable {
        public let configurationName: String
        public let revealArchiveInOrganizer: Bool
        public let customArchiveName: String?
        public let preActions: [ExecutionAction]
        public let postActions: [ExecutionAction]

        public init(configurationName: String,
                    revealArchiveInOrganizer: Bool = true,
                    customArchiveName: String? = nil,
                    preActions: [ExecutionAction] = [],
                    postActions: [ExecutionAction] = []) {
            self.configurationName = configurationName
            self.revealArchiveInOrganizer = revealArchiveInOrganizer
            self.customArchiveName = customArchiveName
            self.preActions = preActions
            self.postActions = postActions
        }
        
        public static func archiveAction(configurationName: String,
                                         revealArchiveInOrganizer: Bool = true,
                                         customArchiveName: String? = nil,
                                         preActions: [ExecutionAction] = [],
                                         postActions: [ExecutionAction] = []) -> ArchiveAction {
            return .init(configurationName: configurationName,
                         revealArchiveInOrganizer: revealArchiveInOrganizer,
                         customArchiveName: customArchiveName,
                         preActions: preActions,
                         postActions: postActions)
        }
    }
}
