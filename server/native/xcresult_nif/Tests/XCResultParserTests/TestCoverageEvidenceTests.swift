import Foundation
import Testing
@testable import XCResultParser

struct TestCoverageEvidenceTests {
    private let evidence = TestCoverageEvidence(
        paths: [
            "/private/tmp/app/Sources/Math.swift",
            "/tmp/app/Sources/Math.swift",
            "/tmp/app/.build/checkouts/Dep/Dep.swift",
            "/Applications/Xcode.app/usr/include/stdio.h",
            "/tmp/app/Tests/MathTests.swift",
        ],
        scopes: [
            .init(kind: .test, module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0, 1, 2, 4]),
            .init(kind: .test, module: "AppTests", suite: "MathTests", name: "testNothingOfOurs()", files: [2, 3]),
            .init(kind: .target, module: "AppTests", suite: "", name: "", files: [0, 3, 4]),
        ],
        overlappedTests: [.init(module: "AppTests", suite: "SwiftTests", name: "overlaps()")]
    )
    private let manifest = XcodeCoverageManifest(rootDirectories: ["/tmp/app", "/private/tmp/app/"], partial: false, files: [])

    @Test func keepsTheFilesOfTheRepositoryUnderOneSpelling() {
        #expect(evidence.inRepository(manifest: manifest) == TestCoverageEvidence(
            paths: ["Sources/Math.swift", "Tests/MathTests.swift"],
            scopes: [
                .init(kind: .test, module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0, 1]),
                .init(kind: .target, module: "AppTests", suite: "", name: "", files: [0, 1]),
            ],
            overlappedTests: [.init(module: "AppTests", suite: "SwiftTests", name: "overlaps()")]
        ))
    }

    @Test func keepsEachFilesLinesAndMergesThoseOfOneFileUnderTwoSpellings() {
        let evidence = TestCoverageEvidence(
            paths: evidence.paths,
            scopes: [.init(
                kind: .test, module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0, 1, 2, 4],
                lines: [[3, 5], [5, 6, 9, 9], [1, 1], []]
            )]
        )

        #expect(evidence.inRepository(manifest: manifest).scopes == [
            .init(
                kind: .test, module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0, 1],
                lines: [[3, 6, 9, 9], []]
            ),
        ])
        #expect(TestCoverageEvidence.Scope.lines(ofRanges: [3, 5, 9, 9, 7]) == IndexSet([3, 4, 5, 9]))
    }

    @Test func keepsWhetherTheRunCollectedEvidenceEvenWithoutScopes() {
        let notLinked = TestCoverageEvidence(paths: [], scopes: [], status: .notLinked)

        #expect(notLinked.inRepository(manifest: manifest).status == .notLinked)
        #expect(TestSummary(testPlanName: nil, status: .passed, duration: nil, testModules: [])
            .applying(coverageEvidence: notLinked).coverageEvidence == notLinked)
        #expect(TestSummary(testPlanName: nil, status: .passed, duration: nil, testModules: [])
            .applying(coverageEvidence: TestCoverageEvidence(
                paths: [],
                scopes: []
            )).coverageEvidence == nil)
    }

    @Test func reachesTheSummaryOnlyWithTheManifestBesideIt() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }

        try evidence.write(toResultBundle: bundle)
        #expect(XCResultParser.coverageEvidence(inResultBundle: bundle) == nil)

        let encoded = try JSONEncoder().encode(manifest)
        try encoded.write(to: bundle.appendingPathComponent(XcodeCoverageManifest.fileName))
        #expect(XCResultParser.coverageEvidence(inResultBundle: bundle)?.paths == ["Sources/Math.swift", "Tests/MathTests.swift"])

        let summary = TestSummary(testPlanName: nil, status: .passed, duration: nil, testModules: [])
        #expect(summary.applying(coverageEvidence: TestCoverageEvidence(paths: [], scopes: [])).coverageEvidence == nil)
    }

    @Test func readsABundleWrittenBeforeOverlappedTestsWereReported() throws {
        let json = #"{"paths": ["Sources/Math.swift"], "scopes": [], "status": "collected"}"#
        let evidence = try JSONDecoder().decode(TestCoverageEvidence.self, from: Data(json.utf8))

        #expect(evidence == TestCoverageEvidence(paths: ["Sources/Math.swift"], scopes: [], status: .collected))
    }
}
