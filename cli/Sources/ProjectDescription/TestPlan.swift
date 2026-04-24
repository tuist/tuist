/// A test plan entry on a `TestAction`.
///
/// Supports both pre-configured `.xctestplan` files maintained by hand and plans whose
/// `.xctestplan` file Tuist generates from Swift. Both kinds can be mixed in a single
/// `TestAction.testPlans(_:)` call.
public enum TestPlan: Equatable, Codable, Sendable {
    /// Reference an existing, hand-maintained `.xctestplan` file.
    ///
    /// The path supports globbing (e.g. `"TestPlans/*.xctestplan"`) — matching files are sorted
    /// and attached in that order.
    case preConfigured(path: Path, isDefault: Bool = false)

    /// Have Tuist generate a `.xctestplan` file from the given test targets.
    ///
    /// By default Tuist writes the file to `Derived/TestPlans/<name>.xctestplan` next to the
    /// manifest — the same derived directory used for synthesized Info.plists and module maps,
    /// which is already gitignored. Pass `path` to pin the file to a specific location when you
    /// need a predictable, checked-in location for external tooling (for example, invoking
    /// `xcodebuild -testPlan` from CI without going through `tuist test`).
    case generated(
        name: String,
        testTargets: [TestableTarget],
        path: Path? = nil,
        isDefault: Bool = false
    )
}
