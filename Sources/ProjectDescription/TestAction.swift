import Foundation

/// It represents the test action of a scheme.
public struct TestAction: Equatable, Codable {
    /// List of test plans. The first in the list will be the default plan.
    public let testPlans: [Path]?

    /// List of targets to be tested.
    public let targets: [TestableTarget]

    /// Arguments passed to the process running the tests.
    public let arguments: Arguments?

    /// Name of the configuration that should be used for building the test targets.
    public let configuration: ConfigurationName

    /// True to collect the test coverage results.
    public let coverage: Bool

    /// List of targets for which Xcode will collect the coverage results.
    public let codeCoverageTargets: [TargetReference]

    /// Set the target that will expand the variables for
    public let expandVariableFromTarget: TargetReference?

    /// List of actions to be executed before running the tests.
    public let preActions: [ExecutionAction]

    /// List of actions to be executed after running the tests.
    public let postActions: [ExecutionAction]

    /// Language.
    public let language: SchemeLanguage?

    /// Region.
    public let region: String?

    /// Diagnostics options.
    public let diagnosticsOptions: [SchemeDiagnosticsOption]

    private init(testPlans: [Path]?,
                 targets: [TestableTarget],
                 arguments: Arguments?,
                 configuration: ConfigurationName,
                 coverage: Bool,
                 codeCoverageTargets: [TargetReference],
                 expandVariableFromTarget: TargetReference?,
                 preActions: [ExecutionAction],
                 postActions: [ExecutionAction],
                 diagnosticsOptions: [SchemeDiagnosticsOption],
                 language: SchemeLanguage?,
                 region: String?)
    {
        self.testPlans = testPlans
        self.targets = targets
        self.arguments = arguments
        self.configuration = configuration
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
        self.codeCoverageTargets = codeCoverageTargets
        self.expandVariableFromTarget = expandVariableFromTarget
        self.diagnosticsOptions = diagnosticsOptions
        self.language = language
        self.region = region
    }

    /// Initializes a test action using a list of targets.
    /// - Parameters:
    ///   - targets: List of targets to be tested.
    ///   - arguments: Arguments passed when running the tests.
    ///   - configuration: Configuration to be used.
    ///   - coverage: Whether test coverage should be collected.
    ///   - codeCoverageTargets: The targets the test coverage should be collected from.
    ///   - expandVariableFromTarget: A target that will be used to expand the variables defined inside Environment Variables definition
    ///   - preActions: Actions to execute before running the tests.
    ///   - postActions: Actions to execute after running the tests.
    ///   - diagnosticsOptions: Diagnostics options.
    ///   - language: The language to be used.
    ///   - region: The region to be used.
    /// - Returns: An initialized test action.
    public static func targets(_ targets: [TestableTarget],
                               arguments: Arguments? = nil,
                               configuration: ConfigurationName = .debug,
                               coverage: Bool = false,
                               codeCoverageTargets: [TargetReference] = [],
                               expandVariableFromTarget: TargetReference? = nil,
                               preActions: [ExecutionAction] = [],
                               postActions: [ExecutionAction] = [],
                               diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker],
                               language: SchemeLanguage? = nil,
                               region: String? = nil) -> Self
    {
        Self(
            testPlans: nil,
            targets: targets,
            arguments: arguments,
            configuration: configuration,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets,
            expandVariableFromTarget: expandVariableFromTarget,
            preActions: preActions,
            postActions: postActions,
            diagnosticsOptions: diagnosticsOptions,
            language: language,
            region: region
        )
    }

    /// Initializes a test action using a list of test plans.
    /// - Parameters:
    ///   - testPlans: List of test plans to run.
    ///   - arguments: Arguments passed when running the tests.
    ///   - configuration: Configuration to be used.
    ///   - coverage: Whether test coverage should be collected.
    ///   - codeCoverageTargets: The targets the test coverage should be collected from.
    ///   - expandVariableFromTarget: A target that will be used to expand the variables defined inside Environment Variables definition
    ///   - preActions: Actions to execute before running the tests.
    ///   - postActions: Actions to execute after running the tests.
    ///   - diagnosticsOptions: Diagnostics options.
    ///   - language: The language to be used.
    ///   - region: The region to be used.
    /// - Returns: An initialized test action.
    public static func testPlans(_ testPlans: [Path],
                                 configuration: ConfigurationName = .debug,
                                 preActions: [ExecutionAction] = [],
                                 postActions: [ExecutionAction] = []) -> Self
    {
        Self(
            testPlans: testPlans,
            targets: [],
            arguments: nil,
            configuration: configuration,
            coverage: false,
            codeCoverageTargets: [],
            expandVariableFromTarget: nil,
            preActions: preActions,
            postActions: postActions,
            diagnosticsOptions: [.mainThreadChecker],
            language: nil,
            region: nil
        )
    }
}
