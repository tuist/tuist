import Foundation

/// You can create a test action with either a set of test targets or test plans using the `.targets` or `.testPlans` static methods respectively.
public struct TestAction: Equatable, Codable {
    /// List of test plans. The first in the list will be the default plan.
    public let testPlans: [Path]?

    /// A list of testable targets, that are targets which are defined in the project with testable information.
    public let targets: [TestableTarget]

    /// Command line arguments passed on launch and environment variables.
    public let arguments: Arguments?

    /// Build configuration to run the test with.
    public let configuration: ConfigurationName

    /// Whether a debugger should be attached to the test process or not.
    public let attachDebugger: Bool

    /// A target that will be used to expand the variables defined inside Environment Variables definition (e.g. $SOURCE_ROOT)
    public let expandVariableFromTarget: TargetReference?

    /// A list of actions that are executed before starting the tests-run process.
    public let preActions: [ExecutionAction]

    /// A list of actions that are executed after the tests-run process.
    public let postActions: [ExecutionAction]

    /// List of options to set to the action.
    public let options: TestActionOptions

    /// List of diagnostics options to set to the action.
    public let diagnosticsOptions: [SchemeDiagnosticsOption]

    private init(
        testPlans: [Path]?,
        targets: [TestableTarget],
        arguments: Arguments?,
        configuration: ConfigurationName,
        attachDebugger: Bool,
        expandVariableFromTarget: TargetReference?,
        preActions: [ExecutionAction],
        postActions: [ExecutionAction],
        options: TestActionOptions,
        diagnosticsOptions: [SchemeDiagnosticsOption]
    ) {
        self.testPlans = testPlans
        self.targets = targets
        self.arguments = arguments
        self.configuration = configuration
        self.attachDebugger = attachDebugger
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
    ///   - attachDebugger: A boolean controlling whether a debugger is attached to the process running the tests.
    ///   - expandVariableFromTarget: A target that will be used to expand the variables defined inside Environment Variables definition
    ///   - preActions: Actions to execute before running the tests.
    ///   - postActions: Actions to execute after running the tests.
    ///   - options: Test options.
    ///   - diagnosticsOptions: Diagnostics options.
    /// - Returns: An initialized test action.
    public static func targets(
        _ targets: [TestableTarget],
        arguments: Arguments? = nil,
        configuration: ConfigurationName = .debug,
        attachDebugger: Bool = true,
        expandVariableFromTarget: TargetReference? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        options: TestActionOptions = .options(),
        diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker]
    ) -> Self {
        Self(
            testPlans: nil,
            targets: targets,
            arguments: arguments,
            configuration: configuration,
            attachDebugger: attachDebugger,
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
    public static func testPlans(
        _ testPlans: [Path],
        configuration: ConfigurationName = .debug,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) -> Self {
        Self(
            testPlans: testPlans,
            targets: [],
            arguments: nil,
            configuration: configuration,
            attachDebugger: true,
            expandVariableFromTarget: nil,
            preActions: preActions,
            postActions: postActions,
            options: .options(),
            diagnosticsOptions: []
        )
    }
}
