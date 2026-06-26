import Foundation

/// Constants shared between the sharding planner (`ShardPlanService`) and runner (`ShardService`).
enum ShardConstants {
    /// Reserved `test_suite_name` marking that an entire module should run rather than a specific suite.
    ///
    /// Suite-granularity sharding normally produces `Module/Suite` units. When `xcodebuild -enumerate-tests`
    /// cannot discover a module's suites — even after per-target recovery — the planner emits a
    /// `Module/<wholeModuleSuiteSentinel>` unit instead of silently dropping the module. The sentinel is an
    /// opaque string to the server (it round-trips through the shard plan unchanged), and the runner
    /// translates it back to a bare `-only-testing <Module>` so the whole module runs. This guarantees a
    /// flaky enumeration can never silently exclude a module's tests from the plan.
    static let wholeModuleSuiteSentinel = "__tuist_whole_module__"
}
