/// An action that tests the built products.
///
/// You can create a test action with either a set of test targets or test plans using the `.targets` or `.testPlans` static
/// methods respectively.
public struct TestAction: Equatable, Codable, Sendable {
    /// List of test plans referenced by path.
    ///
    /// Kept for backwards compatibility — prefer `testPlanEntries` (the `[TestPlan]` overload of
    /// `testPlans(_:)`), which supports both pre-configured files and Tuist-generated plans in a
    /// single list. The first in the list is the default plan.
    public var testPlans: [Path]?

    /// List of test plan entries attached to the action.
    ///
    /// Each entry is either a pre-configured `.xctestplan` file (`TestPlan.preConfigured`) or a
    /// plan whose file Tuist generates from Swift (`TestPlan.generated`). Both kinds can be mixed
    /// freely. If no entry is marked as default, the first one is used.
    public var testPlanEntries: [TestPlan]?

    /// A list of testable targets, that are targets which are defined in the project with testable information.
    public var targets: [TestableTarget]

    /// Command line arguments passed on launch and environment variables.
    public var arguments: Arguments?

    /// Build configuration to run the test with.
    public var configuration: ConfigurationName

    /// Whether a debugger should be attached to the test process or not.
    public var attachDebugger: Bool

    /// A target that will be used to expand the variables defined inside Environment Variables definition (e.g. $SOURCE_ROOT)
    public var expandVariableFromTarget: TargetReference?

    /// A list of actions that are executed before starting the tests-run process.
    public var preActions: [ExecutionAction]

    /// A list of actions that are executed after the tests-run process.
    public var postActions: [ExecutionAction]

    /// List of options to set to the action.
    public var options: TestActionOptions

    /// List of diagnostics options to set to the action.
    public var diagnosticsOptions: SchemeDiagnosticsOptions

    /// List of testIdentifiers to skip to the test
    public var skippedTests: [String]?

    private init(
        testPlans: [Path]?,
        testPlanEntries: [TestPlan]?,
        targets: [TestableTarget],
        arguments: Arguments?,
        configuration: ConfigurationName,
        attachDebugger: Bool,
        expandVariableFromTarget: TargetReference?,
        preActions: [ExecutionAction],
        postActions: [ExecutionAction],
        options: TestActionOptions,
        diagnosticsOptions: SchemeDiagnosticsOptions,
        skippedTests: [String]?
    ) {
        self.testPlans = testPlans
        self.testPlanEntries = testPlanEntries
        self.targets = targets
        self.arguments = arguments
        self.configuration = configuration
        self.attachDebugger = attachDebugger
        self.preActions = preActions
        self.postActions = postActions
        self.expandVariableFromTarget = expandVariableFromTarget
        self.options = options
        self.diagnosticsOptions = diagnosticsOptions
        self.skippedTests = skippedTests
    }

    /// Returns a test action from a list of targets to be tested.
    /// - Parameters:
    ///   - targets: List of targets to be tested.
    ///   - arguments: Arguments passed when running the tests.
    ///   - configuration: Configuration to be used.
    ///   - attachDebugger: A boolean controlling whether a debugger is attached to the process running the tests.
    ///   - expandVariableFromTarget: A target that will be used to expand the variables defined inside Environment Variables
    /// definition. When nil, it does not expand any variables.
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
        diagnosticsOptions: SchemeDiagnosticsOptions = .options(),
        skippedTests: [String] = []
    ) -> Self {
        Self(
            testPlans: nil,
            testPlanEntries: nil,
            targets: targets,
            arguments: arguments,
            configuration: configuration,
            attachDebugger: attachDebugger,
            expandVariableFromTarget: expandVariableFromTarget,
            preActions: preActions,
            postActions: postActions,
            options: options,
            diagnosticsOptions: diagnosticsOptions,
            skippedTests: skippedTests
        )
    }

    /// Returns a test action from a list of test plans referenced by path.
    ///
    /// Each path may include glob patterns. This overload is kept for backwards compatibility;
    /// prefer the `[TestPlan]` overload, which can mix pre-configured and Tuist-generated plans.
    ///
    /// - Parameters:
    ///   - testPlans: List of test plans to run.
    ///   - configuration: Configuration to be used.
    ///   - attachDebugger: A boolean controlling whether a debugger is attached to the process running the tests.
    ///   - preActions: Actions to execute before running the tests.
    ///   - postActions: Actions to execute after running the tests.
    /// - Returns: A test action.
    public static func testPlans(
        _ testPlans: [Path],
        configuration: ConfigurationName = .debug,
        attachDebugger: Bool = true,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) -> Self {
        Self(
            testPlans: testPlans,
            testPlanEntries: nil,
            targets: [],
            arguments: nil,
            configuration: configuration,
            attachDebugger: attachDebugger,
            expandVariableFromTarget: nil,
            preActions: preActions,
            postActions: postActions,
            options: .options(),
            diagnosticsOptions: .options(),
            skippedTests: nil
        )
    }

    /// Returns a test action from a list of test plan entries.
    ///
    /// Each entry is either a `.preConfigured` file or a `.generated` plan Tuist builds from Swift;
    /// both kinds can be mixed. If no entry is marked as default, the first one is used.
    ///
    /// - Parameters:
    ///   - testPlans: List of test plan entries.
    ///   - configuration: Configuration to be used.
    ///   - attachDebugger: A boolean controlling whether a debugger is attached to the process running the tests.
    ///   - preActions: Actions to execute before running the tests.
    ///   - postActions: Actions to execute after running the tests.
    /// - Returns: A test action.
    public static func testPlans(
        _ testPlans: [TestPlan],
        configuration: ConfigurationName = .debug,
        attachDebugger: Bool = true,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) -> Self {
        Self(
            testPlans: nil,
            testPlanEntries: testPlans,
            targets: [],
            arguments: nil,
            configuration: configuration,
            attachDebugger: attachDebugger,
            expandVariableFromTarget: nil,
            preActions: preActions,
            postActions: postActions,
            options: .options(),
            diagnosticsOptions: .options(),
            skippedTests: nil
        )
    }
}
