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
    public let configurationName: String

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
                 configurationName: String,
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
        self.configurationName = configurationName
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
        self.codeCoverageTargets = codeCoverageTargets
        self.expandVariableFromTarget = expandVariableFromTarget
        self.diagnosticsOptions = diagnosticsOptions
        self.language = language
        self.region = region
    }

    /// Initializes a new instance of a test action using targets
    /// - Parameters:
    ///   - targets: targets: List of targets to be tested.
    ///   - configuration: Configuration that should be used for building the test targets.
    ///   - preActions: ist of actions to be executed before running the tests.
    ///   - postActions: List of actions to be executed after running the tests.
    public static func targets(_ targets: [TestableTarget],
                               configuration: PresetBuildConfiguration = .debug,
                               preActions: [ExecutionAction] = [],
                               postActions: [ExecutionAction] = []) -> Self
    {
        Self(
            testPlans: [],
            targets: targets,
            arguments: nil,
            configurationName: configuration.name,
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

    /// Initializes a new instance of a test action using test plans
    /// - Parameters:
    ///   - testPlans: Array of test plans. The first in the array will be the default plan.
    ///   - configuration: Configuration that should be used for building the test targets.
    ///   - preActions: ist of actions to be executed before running the tests.
    ///   - postActions: List of actions to be executed after running the tests.
    public static func testPlans(_ testPlans: [Path],
                                 configuration: PresetBuildConfiguration = .debug,
                                 preActions: [ExecutionAction] = [],
                                 postActions: [ExecutionAction] = []) -> Self
    {
        Self(
            testPlans: testPlans,
            targets: [],
            arguments: nil,
            configurationName: configuration.name,
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
