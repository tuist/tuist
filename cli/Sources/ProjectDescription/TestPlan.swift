/// A test plan entry on a `TestAction`.
///
/// Use `testPlan(path:)` to reference an existing `.xctestplan` file, or
/// `testPlan(name:testTargets:)` to have Tuist generate one from Swift so the list of test
/// targets stays in sync with the manifest as features are added or removed:
///
/// ```swift
/// .testPlans([
///     .testPlan(name: "UnitTests", testTargets: allUnitTests),
///     .testPlan(path: "TestPlans/Legacy.xctestplan"),
/// ])
/// ```
///
/// The first plan in the list is the default. A bare string literal is shorthand for
/// `testPlan(path:)`, and `relativeToManifest(_:)`, `relativeToRoot(_:)`, and
/// `relativeToCurrentFile(_:)` are available as convenience factories for the path form.
public struct TestPlan: Equatable, Codable, Sendable, ExpressibleByStringLiteral {
    /// Describes where the `.xctestplan` comes from: either a path the user maintains or a
    /// specification Tuist uses to generate the file.
    public enum Source: Equatable, Codable, Sendable {
        /// Reference to an existing `.xctestplan` at the given path. Glob patterns are supported.
        case path(Path)

        /// Specification for a plan whose `.xctestplan` file Tuist generates from Swift.
        ///
        /// When `path` is `nil`, Tuist writes the file to `Derived/TestPlans/<name>.xctestplan`
        /// next to the manifest (gitignored alongside other derived artefacts). Set `path` to
        /// pin the file to a specific checked-in location, for example when external tooling
        /// like `xcodebuild -testPlan` needs a predictable path.
        case generated(name: String, testTargets: [TestableTarget], path: Path?)
    }

    public let source: Source

    private init(source: Source) {
        self.source = source
    }

    public init(stringLiteral value: String) {
        self.init(source: .path(Path(stringLiteral: value)))
    }

    /// Reference an existing, hand-maintained `.xctestplan` file.
    ///
    /// The `path` value is a `Path`, which conforms to `ExpressibleByStringLiteral`, so string
    /// literals work directly (e.g. `.testPlan(path: "TestPlans/Foo.xctestplan")`). Glob
    /// patterns are supported — matching files are sorted and attached in that order.
    public static func testPlan(path: Path) -> TestPlan {
        TestPlan(source: .path(path))
    }

    /// Have Tuist generate a `.xctestplan` file from the given test targets.
    ///
    /// By default Tuist writes the file to `Derived/TestPlans/<name>.xctestplan` next to the
    /// manifest. Pass `path` to pin the file to a specific location when you need a predictable,
    /// checked-in location for external tooling.
    public static func testPlan(
        name: String,
        testTargets: [TestableTarget],
        path: Path? = nil
    ) -> TestPlan {
        TestPlan(source: .generated(name: name, testTargets: testTargets, path: path))
    }

    /// Reference a `.xctestplan` file at a path relative to the manifest directory.
    public static func relativeToManifest(_ pathString: String) -> TestPlan {
        .testPlan(path: .relativeToManifest(pathString))
    }

    /// Reference a `.xctestplan` file at a path relative to the closest Tuist or `.git` directory.
    public static func relativeToRoot(_ pathString: String) -> TestPlan {
        .testPlan(path: .relativeToRoot(pathString))
    }

    /// Reference a `.xctestplan` file at a path relative to the file defining the test plan.
    public static func relativeToCurrentFile(
        _ pathString: String,
        callerPath: StaticString = #file
    ) -> TestPlan {
        .testPlan(path: .relativeToCurrentFile(pathString, callerPath: callerPath))
    }
}
