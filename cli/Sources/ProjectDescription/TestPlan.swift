/// A test plan entry on a `TestAction`.
///
/// Supports both hand-maintained `.xctestplan` files (`.path`, `.relativeToManifest`, etc.) and
/// plans whose file Tuist generates from Swift (`.generated`). Both kinds can be mixed in a single
/// `TestAction.testPlans(_:)` call.
///
/// For backwards compatibility with existing manifests, `TestPlan` conforms to
/// `ExpressibleByStringLiteral` — a bare string is treated as `.path(Path(stringLiteral:))`, so
/// `testPlans(["Foo.xctestplan", "Other.xctestplan"])` keeps working unchanged.
public enum TestPlan: Equatable, Codable, Sendable, ExpressibleByStringLiteral {
    /// Reference an existing, hand-maintained `.xctestplan` file at the given path.
    ///
    /// The associated `path` value is a `Path`, which conforms to `ExpressibleByStringLiteral`,
    /// so string literals work directly (e.g. `.path("TestPlans/Foo.xctestplan")`). Glob
    /// patterns are supported — matching files are sorted and attached in that order.
    case path(_ path: Path, isDefault: Bool = false)

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

    public init(stringLiteral value: String) {
        self = .path(Path(stringLiteral: value))
    }

    /// Reference a `.xctestplan` file at a path relative to the manifest directory.
    public static func relativeToManifest(_ pathString: String, isDefault: Bool = false) -> TestPlan {
        .path(.relativeToManifest(pathString), isDefault: isDefault)
    }

    /// Reference a `.xctestplan` file at a path relative to the closest Tuist or `.git` directory.
    public static func relativeToRoot(_ pathString: String, isDefault: Bool = false) -> TestPlan {
        .path(.relativeToRoot(pathString), isDefault: isDefault)
    }

    /// Reference a `.xctestplan` file at a path relative to the file defining the test plan.
    public static func relativeToCurrentFile(
        _ pathString: String,
        callerPath: StaticString = #file,
        isDefault: Bool = false
    ) -> TestPlan {
        .path(.relativeToCurrentFile(pathString, callerPath: callerPath), isDefault: isDefault)
    }
}
