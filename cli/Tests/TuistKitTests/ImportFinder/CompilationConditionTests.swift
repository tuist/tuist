import TuistTesting
import XCTest

@testable import TuistInspectCommand

final class CompilationConditionParserTests: TuistUnitTestCase {
    private var subject: CompilationConditionParser!

    override func setUp() {
        super.setUp()
        subject = CompilationConditionParser()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_parsesBareFlag() throws {
        XCTAssertEqual(try subject.parse("DEBUG"), .flag("DEBUG"))
    }

    func test_parsesCanImport() throws {
        XCTAssertEqual(
            try subject.parse("canImport(FirebaseAppDistribution)"),
            .canImport("FirebaseAppDistribution")
        )
    }

    func test_parsesNegation() throws {
        XCTAssertEqual(try subject.parse("!DEBUG"), .not(.flag("DEBUG")))
    }

    func test_parsesAnd() throws {
        XCTAssertEqual(
            try subject.parse("Live && canImport(FirebaseAppDistribution)"),
            .and(.flag("Live"), .canImport("FirebaseAppDistribution"))
        )
    }

    func test_parsesOr() throws {
        XCTAssertEqual(
            try subject.parse("Debug || Live"),
            .or(.flag("Debug"), .flag("Live"))
        )
    }

    func test_parsesGlovoCompoundExpression() throws {
        // From Tarek's AppDelegate: a real expression mixing flags, parens,
        // and `canImport`. The parser must respect operator precedence so the
        // `&&` binds tighter than `||`.
        let parsed = try subject.parse("Debug || (Live && canImport(FirebaseAppDistribution))")
        XCTAssertEqual(
            parsed,
            .or(
                .flag("Debug"),
                .and(.flag("Live"), .canImport("FirebaseAppDistribution"))
            )
        )
    }

    func test_parsesOsAndArchAndTargetEnvironment() throws {
        XCTAssertEqual(try subject.parse("os(iOS)"), .os("iOS"))
        XCTAssertEqual(try subject.parse("arch(arm64)"), .arch("arm64"))
        XCTAssertEqual(try subject.parse("targetEnvironment(simulator)"), .targetEnvironment("simulator"))
    }

    func test_parsesSwiftAndCompilerVersionComparisons() throws {
        let swift = try subject.parse("swift(>=5.9)")
        XCTAssertEqual(
            swift,
            .swift(.init(operator: .greaterThanOrEqual, version: [5, 9]))
        )
        let compiler = try subject.parse("compiler(<6.0)")
        XCTAssertEqual(
            compiler,
            .compiler(.init(operator: .lessThan, version: [6, 0]))
        )
    }

    func test_parsesTrueAndFalseLiterals() throws {
        XCTAssertEqual(try subject.parse("true"), .literal(true))
        XCTAssertEqual(try subject.parse("false"), .literal(false))
    }
}

final class CompilationConditionEvaluatorTests: TuistUnitTestCase {
    private var parser: CompilationConditionParser!

    override func setUp() {
        super.setUp()
        parser = CompilationConditionParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    private func evaluate(
        _ source: String,
        flagSets: [Set<String>] = [[]],
        platforms: Set<String> = [],
        targetEnvironments: Set<String> = [],
        reachableModules: Set<String> = []
    ) throws -> Bool {
        let context = CompilationConditionContext(
            flagSetsPerConfiguration: flagSets,
            platforms: platforms,
            targetEnvironments: targetEnvironments,
            reachableModules: reachableModules
        )
        return CompilationConditionEvaluator.evaluate(try parser.parse(source), in: context)
    }

    func test_canImportTrueWhenModuleReachable() throws {
        let result = try evaluate(
            "canImport(FirebaseAppDistribution)",
            reachableModules: ["FirebaseAppDistribution"]
        )
        XCTAssertTrue(result)
    }

    func test_canImportFalseWhenModuleAbsent() throws {
        let result = try evaluate(
            "canImport(FirebaseAppDistribution)",
            reachableModules: ["Watchdog"]
        )
        XCTAssertFalse(result)
    }

    func test_compoundExpressionLiveBranchActiveWhenLiveFlagAndModulePresent() throws {
        // Glovo beta variant: `Live` flag is set (release config) and Firebase is declared.
        let result = try evaluate(
            "Debug || (Live && canImport(FirebaseAppDistribution))",
            flagSets: [["Live"]],
            reachableModules: ["FirebaseAppDistribution"]
        )
        XCTAssertTrue(result)
    }

    func test_compoundExpressionFalseForReleaseVariantWithoutFlagsOrModule() throws {
        // Glovo release variant: no Debug, no Live, no Firebase → branch dead.
        let result = try evaluate(
            "Debug || (Live && canImport(FirebaseAppDistribution))",
            flagSets: [[]],
            reachableModules: []
        )
        XCTAssertFalse(result)
    }

    func test_compoundExpressionTrueForDebugVariantViaShortCircuit() throws {
        // If `Debug` is set, the right-hand side never has to be true.
        let result = try evaluate(
            "Debug || (Live && canImport(FirebaseAppDistribution))",
            flagSets: [["Debug"]],
            reachableModules: []
        )
        XCTAssertTrue(result)
    }

    func test_anyConfigurationActivatesExpression() throws {
        // A target with multiple build configurations is "live" if any one
        // of them satisfies the expression.
        let result = try evaluate(
            "Live",
            flagSets: [["Debug"], ["Live"]]
        )
        XCTAssertTrue(result)
    }

    func test_negation() throws {
        let result = try evaluate(
            "!DEBUG",
            flagSets: [[]]
        )
        XCTAssertTrue(result)
    }

    func test_osCheck() throws {
        XCTAssertTrue(try evaluate("os(iOS)", platforms: ["iOS"]))
        XCTAssertFalse(try evaluate("os(macOS)", platforms: ["iOS"]))
    }

    func test_swiftVersionGate() throws {
        let context = CompilationConditionContext(swiftVersion: [5, 9, 0])
        XCTAssertTrue(
            CompilationConditionEvaluator.evaluate(
                try parser.parse("swift(>=5.9)"),
                in: context
            )
        )
        XCTAssertFalse(
            CompilationConditionEvaluator.evaluate(
                try parser.parse("swift(>=6.0)"),
                in: context
            )
        )
    }
}
