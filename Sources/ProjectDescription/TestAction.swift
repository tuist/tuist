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

    /// Set the target that will expand the variables for
    public let expandVariableFromTarget: TargetReference?

    /// List of actions to be executed before running the tests.
    public let preActions: [ExecutionAction]

    /// List of actions to be executed after running the tests.
    public let postActions: [ExecutionAction]

    /// Options.
    public let options: TestActionOptions

    /// Diagnostics options.
    public let diagnosticsOptions: [SchemeDiagnosticsOption]

    private init(testPlans: [Path]?,
                 targets: [TestableTarget],
                 arguments: Arguments?,
                 configuration: ConfigurationName,
                 expandVariableFromTarget: TargetReference?,
                 preActions: [ExecutionAction],
                 postActions: [ExecutionAction],
                 options: TestActionOptions,
                 diagnosticsOptions: [SchemeDiagnosticsOption])
    {
        self.testPlans = testPlans
        self.targets = targets
        self.arguments = arguments
        self.configuration = configuration
        self.preActions = preActions
        self.postActions = postActions
        self.expandVariableFromTarget = expandVariableFromTarget
        self.options = options
        self.diagnosticsOptions = diagnosticsOptions
    }

    /// Initializes a test action using a list of targets.
    /// - Parameters:
    ///   - targets: List of targets to be tested.
    ///   - arguments: Arguments passed when running the tests.
    ///   - configuration: Configuration to be used.
    ///   - expandVariableFromTarget: A target that will be used to expand the variables defined inside Environment Variables definition
    ///   - preActions: Actions to execute before running the tests.
    ///   - postActions: Actions to execute after running the tests.
    ///   - options: Test options.
    ///   - diagnosticsOptions: Diagnostics options.
    /// - Returns: An initialized test action.
    public static func targets(_ targets: [TestableTarget],
                               arguments: Arguments? = nil,
                               configuration: ConfigurationName = .debug,
                               expandVariableFromTarget: TargetReference? = nil,
                               preActions: [ExecutionAction] = [],
                               postActions: [ExecutionAction] = [],
                               options: TestActionOptions = .options(),
                               diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker]) -> Self
    {
        Self(
            testPlans: nil,
            targets: targets,
            arguments: arguments,
            configuration: configuration,
            expandVariableFromTarget: expandVariableFromTarget,
            preActions: preActions,
            postActions: postActions,
            options: options,
            diagnosticsOptions: diagnosticsOptions
        )
    }

    /// Initializes a test action using a list of test plans.
    /// - Parameters:
    ///   - testPlans: List of test plans to run.
    ///   - configuration: Configuration to be used.
    ///   - preActions: Actions to execute before running the tests.
    ///   - postActions: Actions to execute after running the tests.
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
            expandVariableFromTarget: nil,
            preActions: preActions,
            postActions: postActions,
            options: .options(),
            diagnosticsOptions: []
        )
    }
}
