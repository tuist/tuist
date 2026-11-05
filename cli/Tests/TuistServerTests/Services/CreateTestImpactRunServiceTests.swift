import Foundation
import OpenAPIRuntime
import Testing

@testable import TuistServer

struct CreateTestImpactRunServiceTests {
    private typealias Output = Operations.createTestImpactRun.Output

    private func request(
        _ basis: TestImpactRunRequest.Basis,
        parentSHAs: [String] = ["base", "head"],
        ancestorSHAs: [String] = []
    ) -> TestImpactRunRequest {
        TestImpactRunRequest(
            headSHA: "head",
            commitSHA: "merge",
            parentSHAs: parentSHAs,
            ancestorSHAs: ancestorSHAs,
            basis: basis,
            modules: ["CoreTests"],
            skippedModules: ["CachedTests"],
            platform: "ios",
            gitBranch: "feature/discount",
            scheme: "Shop",
            testPlan: nil,
            destination: nil
        )
    }

    @Test func sendsTheBaselineAndTheDiffInPathOrder() {
        let body = CreateTestImpactRunService.body(for: request(.baseline(
            sha: "baseline",
            changedFiles: [
                TestImpactChangedFile(
                    path: "Core/Sources/Money.swift",
                    status: "M",
                    blob: "b2",
                    affectedModules: ["CoreTests"]
                ),
                TestImpactChangedFile(path: "Configs/Base.xcconfig", status: "M", blob: "b1", affectedModules: nil),
                TestImpactChangedFile(path: "Core/Sources/Old.swift", status: "D", blob: nil, affectedModules: []),
            ],
            dirty: false
        )))

        #expect(body.baseline_sha == "baseline")
        #expect(body.fallback_reason == nil)
        #expect(body.head_sha == "head")
        #expect(body.commit_sha == "merge")
        #expect(body.parent_shas == ["base", "head"])
        #expect(body.build_system == "xcode")
        // Every module in scope, by name, with the ones hashing skipped marked.
        #expect(body.modules == [.init(name: "CachedTests", skipped: true), .init(name: "CoreTests", skipped: false)])
        #expect(body.platform == "ios")
        #expect(body.git_branch == "feature/discount")
        #expect(body.xcode == .init(destination: nil, scheme: "Shop", test_plan: nil))
        #expect(body.dirty == nil)
        #expect(body.changed_files_count == 3)
        #expect(body.changed_files == [
            .init(affected_modules: nil, blob: "b1", path: "Configs/Base.xcconfig", status: "M"),
            .init(affected_modules: ["CoreTests"], blob: "b2", path: "Core/Sources/Money.swift", status: "M"),
            .init(affected_modules: [], blob: nil, path: "Core/Sources/Old.swift", status: "D"),
        ])
    }

    @Test func capsTheDiffAndSendsTheTotal() {
        let files = (0 ..< 5002).reversed().map {
            TestImpactChangedFile(path: String(format: "bulk/%04d.txt", $0), status: "A", blob: "b\($0)", affectedModules: [])
        }

        let body = CreateTestImpactRunService.body(for: request(.baseline(sha: "baseline", changedFiles: files, dirty: true)))

        #expect(body.changed_files?.count == 5000)
        #expect(body.changed_files?.first?.path == "bulk/0000.txt")
        #expect(body.changed_files?.last?.path == "bulk/4999.txt")
        #expect(body.changed_files_count == 5002)
        #expect(body.dirty == true)
    }

    @Test func sendsNoDiffWhenTheServerHasIt() {
        let body = CreateTestImpactRunService.body(for: request(.baseline(sha: "baseline", changedFiles: nil, dirty: false)))

        #expect(body.changed_files == nil)
        #expect(body.changed_files_count == nil)
    }

    @Test func sendsNoParentsOrAncestorsWhenThereAreNone() {
        let body = CreateTestImpactRunService.body(for: request(.fallback(.noBaseline), parentSHAs: []))

        #expect(body.parent_shas == nil)
        #expect(body.ancestor_shas == nil)
    }

    @Test func sendsTheAncestorsTheBaselineRequestSent() {
        let body = CreateTestImpactRunService.body(for: request(
            .fallback(.historyUnknown),
            ancestorSHAs: ["parent", "grandparent"]
        ))

        #expect(body.ancestor_shas == ["parent", "grandparent"])
    }

    @Test func sendsTheFallbackReasonWithoutABaseline() {
        let body = CreateTestImpactRunService.body(for: request(.fallback(.historyUnavailable)))

        #expect(body.baseline_sha == nil)
        #expect(body.fallback_reason == "history_unavailable")
        #expect(body.changed_files == nil)
    }

    @Test func returnsTheSelectedTests() {
        let response = Output.ok(.init(body: .json(.init(
            counts: .init(requested: 11, selected: 5, skipped: 6),
            id: "run-id",
            outcome: "selected",
            skipped_tests: [
                .init(module: "CatalogTests"),
                .init(module: "CoreTests", name: "testFormatsDollars", suite: "MoneyTests"),
            ]
        ))))

        #expect(CreateTestImpactRunService.outcome(from: response) == .selected(TestImpactSelection(
            runID: "run-id",
            requested: 11,
            selected: 5,
            skipped: 6,
            skippedTests: [
                SkippedTest(module: "CatalogTests", suite: nil, name: nil),
                SkippedTest(module: "CoreTests", suite: "MoneyTests", name: "testFormatsDollars"),
            ]
        )))
    }

    @Test func returnsTheRecordedFallback() {
        let response = Output.ok(.init(body: .json(.init(
            id: "run-id",
            matched_path: "Configs/Base.xcconfig",
            outcome: "fallback",
            reason: "tracked_file_changed"
        ))))

        #expect(
            CreateTestImpactRunService.outcome(from: response)
                == .fallback(runID: "run-id", reason: .trackedFileChanged, matchedPath: "Configs/Base.xcconfig")
        )
    }

    @Test func treatsAnUnknownOutcomeAsAFallback() {
        let response = Output.ok(.init(body: .json(.init(id: "run-id", outcome: "a_newer_outcome"))))

        #expect(CreateTestImpactRunService.outcome(from: response) == .fallback(runID: "run-id", reason: nil, matchedPath: nil))
    }

    @Test func fallsBackWithoutARecordOnAnErrorResponse() {
        #expect(
            CreateTestImpactRunService.outcome(from: .notFound(.init(body: .json(.init(
                message: "Test impact analysis isn't enabled for this project."
            ))))) == .failed("Test impact analysis isn't enabled for this project.")
        )
        #expect(
            CreateTestImpactRunService.outcome(from: .badRequest(.init(body: .json(.init(message: "Invalid params")))))
                == .failed("Invalid params")
        )
        #expect(
            CreateTestImpactRunService.outcome(from: .undocumented(statusCode: 501, .init()))
                == .failed("The test impact run request failed with an unknown Tuist response of 501.")
        )
    }
}
