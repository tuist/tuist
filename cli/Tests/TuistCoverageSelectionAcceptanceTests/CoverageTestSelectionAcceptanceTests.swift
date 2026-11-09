import FileSystem
import Foundation
import Path
import TuistAcceptanceTesting
import TuistEnvironment
import TuistEnvironmentTesting
import TuistKit
import TuistLoggerTesting
import TuistLogging
import TuistNooraTesting
import TuistServer
import TuistTestCommand
import TuistTesting
import TuistTestSupport
import XCTest

/// Coverage-based test selection end to end. The test records a full run of the Shop fixture on
/// `main` against a fresh project, makes changes, runs `tuist test` after each and checks a few
/// tests each change must or mustn't run. XCTest rather than Swift Testing, so selection can skip
/// these tests one by one once it applies to this suite.
final class CoverageTestSelectionAcceptanceTests: XCTestCase {
    /// The changes share one baseline, since recording it is the slowest step. Each starts from the
    /// baseline commit on a branch of its own, so none sees another's commits. The project's
    /// evidence is shared, though: a test's version recorded on any branch counts wherever its files
    /// have the same content. No two changes may give a file the same content, or one change's run
    /// records the evidence that lets a later one skip the tests it asserts ran, depending on
    /// whether the server ingested it before the later run asked.
    func test_changes_select_against_one_baseline() async throws {
        try await withShop { shop in
            do {
                // The only parallel run: the evidence of processes in simulator clones, which Xcode
                // deletes after the run, maps back to build products. Only the baseline records the
                // evidence the UI change relies on, so the changes run serially. Sharded, so the
                // server must merge the shards' evidence into one baseline.
                try await shop.recordBaseline(sharded: true, parallelTesting: true)
            } catch {
                XCTFail("Recording the baseline failed, so no change ran: \(error)")
                return
            }
            let baseline = try shop.git.head()
            let changes: [(String, (Shop) async throws -> Void)] = [
                ("A source change", sourceChangeRunsTheTestsThatExecutedIt),
                ("A test file change", testFileChangeRunsItsSuite),
                ("A Swift Testing change", swiftTestingChangeRunsTheTestsThatExecutedIt),
                ("A merge checkout", mergeCheckoutFindsTheBaselineThroughItsAncestors),
                ("An app change", appChangeRunsTheUITestsThatLaunchedIt),
                ("A sharded checkout", shardedCheckoutSelectsLikeAnUnshardedOne),
            ]
            for (name, change) in changes {
                do {
                    try shop.git.run("checkout", "-q", "-f", "--detach", baseline)
                    try await change(shop)
                } catch {
                    XCTFail("\(name) failed: \(error)")
                }
            }
        }
    }

    private func sourceChangeRunsTheTestsThatExecutedIt(_ shop: Shop) async throws {
        try shop.git.run("checkout", "-q", "-b", "feature/discount")
        try shop.git.edit("Core/Sources/Discount.swift", replacing: "(100 - percent)", with: "(-percent + 100)")
        try shop.git.commitAll("Refactor the discount calculation")

        let run = try await shop.test()

        XCTAssertTrue(run.selected, run.output)
        XCTAssertTrue(run.ran("DiscountTests/testTenPercentOff"), run.output)
        XCTAssertTrue(run.ran("RoundingTests/testRoundsDownToWholeCents"), run.output)
        XCTAssertFalse(run.ran("MoneyTests/testFormatsDollars"), run.output)
        // A Swift Testing test skipped on its own, in a module that runs: the trait cancels it.
        XCTAssertTrue(run.ran("CartTests/discountAppliesToTotal"), run.output)
        XCTAssertFalse(run.ran("CartTests/totalSumsItems"), run.output)
    }

    private func testFileChangeRunsItsSuite(_ shop: Shop) async throws {
        try shop.git.run("checkout", "-q", "-b", "feature/discount-tests")
        try shop.git.edit(
            "CoreTests/DiscountTests.swift",
            replacing: "Money(cents: 1000)), Money(cents: 900))",
            with: "Money(cents: 1000)), Money(cents: 900), \"10% off $10.00 is $9.00\")"
        )
        try shop.git.commitAll("Explain the discount assertion")

        let run = try await shop.test()

        XCTAssertTrue(run.selected, run.output)
        XCTAssertTrue(run.ran("DiscountTests/testZeroPercentKeepsPrice"), run.output)
        XCTAssertFalse(run.ran("MoneyTests/testAddsAmounts"), run.output)
        XCTAssertFalse(run.ran("RoundingTests/testRoundsDownToWholeCents"), run.output)
    }

    /// The fixture's Swift Testing suites have TestCoverageAttribution's `.coverageAttribution` trait,
    /// so their tests record per-test evidence and the trait cancels the ones selection skips.
    private func swiftTestingChangeRunsTheTestsThatExecutedIt(_ shop: Shop) async throws {
        try shop.git.run("checkout", "-q", "-b", "feature/search")
        try shop.git.edit(
            "Catalog/Sources/Search.swift",
            replacing: "query.isEmpty || name.localizedCaseInsensitiveContains(query)",
            with: "if query.isEmpty { return true }\n        return name.localizedCaseInsensitiveContains(query)"
        )
        try shop.git.commitAll("Return early from an empty search")

        let run = try await shop.test()

        XCTAssertTrue(run.selected, run.output)
        XCTAssertTrue(run.ran("SearchTests/matchesName"), run.output)
        XCTAssertFalse(run.ran("CartTests/totalSumsItems"), run.output)
        XCTAssertFalse(run.ran("ShopUITests/testShowsCatalog"), run.output)
    }

    /// A pull request's merge checkout whose parents the server has never seen: `main` moved on
    /// without a run, and the branch head never ran. The CLI sends the checkout's ancestors so the
    /// server can still find the baseline, and both sides' changes select tests. The discount
    /// changes differently from the source change's, which would otherwise have recorded the
    /// evidence that lets this checkout skip `testTenPercentOff`.
    private func mergeCheckoutFindsTheBaselineThroughItsAncestors(_ shop: Shop) async throws {
        try shop.git.run("checkout", "-q", "-b", "feature/discount-order")
        try shop.git.edit(
            "Core/Sources/Discount.swift",
            replacing: "price.cents * (100 - percent)",
            with: "(100 - percent) * price.cents"
        )
        try shop.git.commitAll("Reorder the discount calculation")
        try shop.git.run("checkout", "-q", "main")
        try shop.git.edit(
            "Catalog/Sources/Catalog.swift",
            replacing: "products.first { $0.sku == sku }",
            with: "products.first(where: { $0.sku == sku })"
        )
        try shop.git.commitAll("Look products up with first(where:)")
        try shop.git.run("checkout", "-q", "--detach", "main")
        try shop.git.run("merge", "-q", "--no-ff", "-m", "Merge feature/discount-order into main", "feature/discount-order")

        let run = try await shop.test(environment: [
            "GITHUB_REF": "refs/pull/1/merge",
            "GITHUB_BASE_REF": "main",
            "GITHUB_HEAD_REF": "feature/discount-order",
        ])

        XCTAssertTrue(run.selected, run.output)
        XCTAssertTrue(run.ran("DiscountTests/testTenPercentOff"), run.output)
        XCTAssertTrue(run.ran("CatalogLoadingTests/testLookupBySKU"), run.output)
        XCTAssertFalse(run.ran("MoneyTests/testFormatsDollars"), run.output)
    }

    /// A UI test's evidence is what the app process it launched executed, including an app launched
    /// in a class `setUp` for the whole suite.
    private func appChangeRunsTheUITestsThatLaunchedIt(_ shop: Shop) async throws {
        try shop.git.run("checkout", "-q", "-b", "feature/receipt")
        try shop.git.edit(
            "App/Sources/Receipt.swift",
            replacing: "var lines = items.map",
            with: "var lines: [String] = items.map"
        )
        try shop.git.commitAll("Spell out the receipt lines' type")

        let run = try await shop.test()

        XCTAssertTrue(run.selected, run.output)
        XCTAssertTrue(run.ran("RelaunchUITests/testDiscountAfterRelaunch"), run.output)
        XCTAssertTrue(run.ran("SharedAppUITests/testShowsReceipt"), run.output)
        XCTAssertFalse(run.ran("ShopUITests/testShowsCatalog"), run.output)
    }

    /// A source change whose checkout runs as two shards from prebuilt test products: the selection
    /// must match an unsharded run's.
    private func shardedCheckoutSelectsLikeAnUnshardedOne(_ shop: Shop) async throws {
        try shop.git.run("checkout", "-q", "-b", "feature/discount-grouping")
        try shop.git.edit(
            "Core/Sources/Discount.swift",
            replacing: "price.cents * (100 - percent) / 100",
            with: "(price.cents * (100 - percent)) / 100"
        )
        try shop.git.commitAll("Group the discount product")

        let run = try await shop.test(sharded: true)

        XCTAssertTrue(run.selected, run.output)
        XCTAssertTrue(run.ran("DiscountTests/testTenPercentOff"), run.output)
        XCTAssertFalse(run.ran("ReceiptTests/testListsItems"), run.output)
        XCTAssertFalse(run.ran("SharedAppUITests/testShowsTotal"), run.output)
    }

    private func withShop(_ body: (Shop) async throws -> Void) async throws {
        // Only these reach the CLI and, through it, the fixture's xcodebuild. Inheriting the whole
        // environment would hand the fixture this process's own coverage and TestCoverageAttribution
        // variables when the suite runs with coverage.
        try await withMockedEnvironment(inheritingVariables: ["PATH", "DEVELOPER_DIR", "TUIST_URL"]) {
            try await withMockedNoora {
                try await withMockedLogger(forwardLogs: true) {
                    try await withFixtureConnectedToCanary(
                        "CoverageTestSelection",
                        fixturesDirectory: TestPaths.fixturesDirectory
                    ) {
                        try await body(try await Shop.make())
                    }
                }
            }
        }
    }
}

/// The fixture as a git repository connected to the test's project.
private struct Shop {
    static let destination = "platform=iOS Simulator,name=iPhone 17"

    let directory: AbsolutePath
    let git: GitRepository
    let fullHandle: String
    let serverURL: URL

    struct Run {
        let output: String
        let tests: Set<String>

        /// Whether the server selected tests, rather than falling back to running every test.
        var selected: Bool {
            output.contains("Coverage-based test selection: ")
        }

        /// Whether `suite/name` ran, passed or failed.
        func ran(_ test: String) -> Bool {
            tests.contains(test)
        }
    }

    static func make() async throws -> Shop {
        let directory = try XCTUnwrap(TuistTest.fixtureDirectory)
        let fullHandle = try XCTUnwrap(TuistTest.fixtureFullHandle)
        let serverURL = try XCTUnwrap(TuistTest.fixtureServerURL)
        try await FileSystem().writeText(
            """
            import ProjectDescription

            let tuist = Tuist(
                fullHandle: "\(fullHandle)",
                testInsights: .testInsights(
                    coverage: .coverage(upload: true),
                    selectiveTesting: .selectiveTesting(strategy: .coverage())
                ),
                url: "\(serverURL.absoluteString)",
                project: .tuist()
            )
            """,
            at: directory.appending(component: "Tuist.swift"),
            options: Set([.overwrite])
        )
        try await TuistTest.run(InstallCommand.self, ["--path", directory.pathString])

        // The CLI finds the repository, and with it the run's commit, from where it runs.
        try XCTUnwrap(Environment.mocked).currentWorkingDirectoryStub = directory
        let git = GitRepository(path: directory)
        try git.run("init", "-q", "-b", "main")
        // The server keys commit history by repository URL, so each project gets its own.
        try git.run(
            "remote",
            "add",
            "origin",
            "https://github.com/tuist-acceptance/\(fullHandle.replacingOccurrences(of: "/", with: "-")).git"
        )
        // A shard plan without a recognized CI provider writes its matrix into the working directory.
        try "\n.tuist-shard-matrix.json\n".write(
            to: directory.appending(components: ".git", "info", "exclude").url,
            atomically: true,
            encoding: .utf8
        )
        try git.commitAll("Shop")
        return Shop(
            directory: directory,
            git: git,
            fullHandle: fullHandle,
            serverURL: serverURL
        )
    }

    /// Runs every test on `main` with `--no-selective-testing`, as a default branch's CI does, and
    /// waits until the server can use the run as a baseline.
    func recordBaseline(sharded: Bool = false, parallelTesting: Bool = false) async throws {
        let baseline = try await test(sharded: sharded, selectiveTesting: false, parallelTesting: parallelTesting)
        // Every assertion that a test didn't run relies on reading the results right.
        guard baseline.tests.count == 19 else {
            throw BaselineError(description: "Not all of the fixture's 19 tests are in the output:\n\(baseline.output)")
        }
        try await waitForBaseline(at: try git.head())
    }

    /// Runs `tuist test`. Sharded, it plans two shards with `--build-only` and runs each with
    /// `--without-building` from the plan's test products, the way a sharded CI workflow does.
    func test(
        environment: [String: String] = [:],
        sharded: Bool = false,
        selectiveTesting: Bool = true,
        parallelTesting: Bool = false
    ) async throws -> Run {
        let mockedEnvironment = try XCTUnwrap(Environment.mocked)
        let previous = mockedEnvironment.variables
        defer { mockedEnvironment.variables = previous }
        mockedEnvironment.variables.merge(environment) { _, new in new }

        let options = (selectiveTesting ? [] : ["--no-selective-testing"]) + passthrough
            // Parallel testing boots simulator clones on every run, which costs more than it saves
            // for a fixture this size and, on a busy machine, stalls a launch for minutes or fails
            // to launch the UI test runner.
            + (parallelTesting ? [] : ["-parallel-testing-enabled", "NO"])
        Logger.testingLogHandler.flush()
        if sharded {
            let reference = "acceptance-\(UUID().uuidString.prefix(8))"
            // Module granularity: a fresh project has no suite timings, and suite granularity puts
            // every suite in the one catch-all shard.
            try await TuistTest.run(TestCommand.self, [
                "Shop", "--build-only", "--shard-total", "2", "--shard-granularity", "module",
                "--shard-reference", reference, "--derived-data-path", derivedData("build").pathString,
            ] + options)
            let matrix = try JSONSerialization.jsonObject(
                with: Data(contentsOf: directory.appending(component: ".tuist-shard-matrix.json").url)
            ) as? [String: Any]
            let shardCount = try XCTUnwrap(matrix?["shard_count"] as? Int)
            XCTAssertEqual(shardCount, 2, "The server didn't plan the two shards this test is about")
            for index in 0 ..< shardCount {
                try await TuistTest.run(TestCommand.self, [
                    "Shop", "--without-building", "--shard-index", "\(index)", "--shard-reference", reference,
                    "--derived-data-path", derivedData("shard-\(index)").pathString,
                ] + options)
            }
        } else {
            try await TuistTest.run(TestCommand.self, [
                "Shop", "--derived-data-path", derivedData("build").pathString,
            ] + options)
        }
        let output = Logger.testingLogHandler.collected[.trace, <=] + "\n" + ui()
        resetUI()
        return Run(output: output, tests: Self.tests(in: output))
    }

    private var passthrough: [String] {
        ["--path", directory.pathString, "--inspect-mode", "local", "--", "-destination", Self.destination]
    }

    private func derivedData(_ name: String) -> AbsolutePath {
        directory.parentDirectory.appending(components: "derived-data", name)
    }

    /// The tests xcodebuild reported as passed or failed, as `suite/name`. A parallel run names the
    /// suite on every result line; a serial one on the line that starts the suite.
    static func tests(in output: String) -> Set<String> {
        let suiteStart = try! Regex(#"^(?:Test Suite '(\w+)'|Suite (\w+)) started"#)
        let result = try! Regex(#"^\s*[✔✖] (?:\[(\w+)\] )?(\w+)(?:\(\))?[ ,(]"#)
        var suite: Substring?
        var tests = Set<String>()
        for line in output.split(separator: "\n") {
            if let match = line.firstMatch(of: suiteStart) {
                suite = match.output[1].substring ?? match.output[2].substring
            } else if let match = line.firstMatch(of: result),
                      let name = match.output[2].substring,
                      let suite = match.output[1].substring ?? suite
            {
                tests.insert("\(suite)/\(name)")
            }
        }
        return tests
    }

    /// The server ingests a run's coverage after the upload, and a baseline only counts once it has.
    private func waitForBaseline(at sha: String) async throws {
        let service = ResolveTestImpactBaselineService(timeout: .seconds(10))
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            let resolution = await service.resolveTestImpactBaseline(
                fullHandle: fullHandle,
                serverURL: serverURL,
                commitSHA: sha,
                parentSHAs: [],
                ancestorSHAs: [],
                platform: "ios",
                scheme: "Shop",
                testPlan: nil,
                destination: Self.destination
            )
            if case .baseline = resolution { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw BaselineError(description: "The server didn't take the run on \(sha) as a baseline within 5 minutes")
    }

    /// Thrown rather than asserted: no change can be checked against a baseline that failed.
    struct BaselineError: Error, CustomStringConvertible {
        let description: String
    }
}
