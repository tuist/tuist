/// A test plan entry on a `TestAction`.
///
/// Use `.path(...)` to reference an existing `.xctestplan` file, or `.generated(...)` to have
/// Tuist generate one from Swift so the list of test targets stays in sync with the manifest
/// as features are added or removed:
///
/// ```swift
/// .testPlans([
///     .generated(name: "UnitTests", testTargets: allUnitTests),
///     .path("TestPlans/Legacy.xctestplan"),
/// ])
/// ```
///
/// The first plan in the list is the default. A bare string literal is shorthand for `.path`,
/// and `relativeToManifest(_:)`, `relativeToRoot(_:)`, and `relativeToCurrentFile(_:)` are
/// available as convenience factories for the path form.
public enum TestPlan: Equatable, Codable, Sendable, ExpressibleByStringLiteral {
    /// Reference an existing, hand-maintained `.xctestplan` file.
    ///
    /// The associated `path` is a `Path`, which conforms to `ExpressibleByStringLiteral`, so
    /// string literals work directly (e.g. `.path("TestPlans/Foo.xctestplan")`). Glob patterns
    /// are supported — matching files are sorted and attached in that order.
    case path(_ path: Path)

    /// Have Tuist generate a `.xctestplan` file from the given test targets.
    ///
    /// When `path` is `nil`, Tuist writes the file to `Derived/TestPlans/<name>.xctestplan`
    /// next to the manifest (gitignored alongside other derived artefacts). Set `path` to pin
    /// the file to a specific checked-in location, for example when external tooling like
    /// `xcodebuild -testPlan` needs a predictable path.
    case generated(name: String, testTargets: [TestableTarget], path: Path? = nil)

    public init(stringLiteral value: String) {
        self = .path(Path(stringLiteral: value))
    }

    /// Reference a `.xctestplan` file at a path relative to the manifest directory.
    public static func relativeToManifest(_ pathString: String) -> TestPlan {
        .path(.relativeToManifest(pathString))
    }

    /// Reference a `.xctestplan` file at a path relative to the closest Tuist or `.git` directory.
    public static func relativeToRoot(_ pathString: String) -> TestPlan {
        .path(.relativeToRoot(pathString))
    }

    /// Reference a `.xctestplan` file at a path relative to the file defining the test plan.
    public static func relativeToCurrentFile(
        _ pathString: String,
        callerPath: StaticString = #file
    ) -> TestPlan {
        .path(.relativeToCurrentFile(pathString, callerPath: callerPath))
    }
}
