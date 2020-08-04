import Foundation

/// It represents the test action of a scheme.
public struct TestAction: Equatable, Codable {
    /// List of targets to be tested.
    public let targets: [TestableTarget]

    /// Arguments passed to the process running the tests.
    public let arguments: Arguments?

    /// Name of the configuration that should be used for building the test targets.
    public let configurationName: String

    /// True to collect the test coverage results.
    public let coverage: Bool

    /// List of targets for which Xcode will collect the coverage results.
    public let codeCoverageTargets: [TargetReference]

    /// List of actions to be executed before running the tests.
    public let preActions: [ExecutionAction]

    /// List of actions to be executed after running the tests.
    public let postActions: [ExecutionAction]

    /// Language
    public let language: String?

    /// Region
    public let region: String?

    /// Diagnostics options.
    public let diagnosticsOptions: [SchemeDiagnosticsOption]

    /// Initializes a new instance of a test action
    /// - Parameters:
    ///   - targets: List of targets to be tested.
    ///   - arguments: Arguments passed to the process running the tests.
    ///   - configurationName: Name of the configuration that should be used for building the test targets.
    ///   - coverage: True to collect the test coverage results.
    ///   - codeCoverageTargets: List of targets for which Xcode will collect the coverage results.
    ///   - preActions: ist of actions to be executed before running the tests.
    ///   - postActions: List of actions to be executed after running the tests.
    ///   - diagnosticsOptions: Diagnostics options.
    ///   - language: Language (e.g. "pl")
    ///   - region: Region (e.g. "PL")
    public init(targets: [TestableTarget] = [],
                arguments: Arguments? = nil,
                configurationName: String,
                coverage: Bool = false,
                codeCoverageTargets: [TargetReference] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = [],
                diagnosticsOptions: [SchemeDiagnosticsOption] = [],
                language: String? = nil,
                region: String? = nil)
    {
        self.targets = targets
        self.arguments = arguments
        self.configurationName = configurationName
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
        self.codeCoverageTargets = codeCoverageTargets
        self.diagnosticsOptions = diagnosticsOptions
        self.language = language
        self.region = region
    }

    /// Initializes a new instance of a test action
    /// - Parameters:
    ///   - targets: List of targets to be tested.
    ///   - arguments: Arguments passed to the process running the tests.
    ///   - config: Configuration that should be used for building the test targets.
    ///   - coverage: True to collect the test coverage results.
    ///   - codeCoverageTargets: List of targets for which Xcode will collect the coverage results.
    ///   - preActions: ist of actions to be executed before running the tests.
    ///   - postActions: List of actions to be executed after running the tests.
    ///   - diagnosticsOptions: Diagnostics options.
    ///   - language: Language (e.g. "pl")
    ///   - region: Region (e.g. "PL")
    public init(targets: [TestableTarget],
                arguments: Arguments? = nil,
                config: PresetBuildConfiguration = .debug,
                coverage: Bool = false,
                codeCoverageTargets: [TargetReference] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = [],
                diagnosticsOptions: [SchemeDiagnosticsOption] = [],
                language: String? = nil,
                region: String? = nil)
    {
        self.init(targets: targets,
                  arguments: arguments,
                  configurationName: config.name,
                  coverage: coverage,
                  codeCoverageTargets: codeCoverageTargets,
                  preActions: preActions,
                  postActions: postActions,
                  diagnosticsOptions: diagnosticsOptions,
                  language: language,
                  region: region)
    }
}
