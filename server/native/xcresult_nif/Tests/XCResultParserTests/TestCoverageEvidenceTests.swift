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
        unattributedTests: 2
    )
    private let manifest = XcodeCoverageManifest(rootDirectories: ["/tmp/app", "/private/tmp/app/"], partial: false, files: [])

    @Test func keepsTheFilesOfTheRepositoryUnderOneSpelling() {
        #expect(evidence.inRepository(manifest: manifest) == TestCoverageEvidence(
            paths: ["Sources/Math.swift", "Tests/MathTests.swift"],
            scopes: [
                .init(kind: .test, module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0, 1]),
                .init(kind: .target, module: "AppTests", suite: "", name: "", files: [0, 1]),
            ],
            unattributedTests: 2
        ))
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
}
