import Foundation
import OpenAPIRuntime
import Testing

@testable import TuistServer

struct ResolveTestImpactBaselineServiceTests {
    private typealias Output = Operations.resolveTestImpactBaseline.Output

    private func ok(baselineSHA: String?, reason: String?, diffCached: Bool?) -> Output {
        .ok(.init(body: .json(.init(baseline_sha: baselineSHA, diff_cached: diffCached, reason: reason))))
    }

    @Test func returnsTheBaselineAndWhetherTheDiffIsStored() {
        #expect(
            ResolveTestImpactBaselineService.resolution(from: ok(baselineSHA: "abc123", reason: nil, diffCached: true))
                == .baseline(sha: "abc123", diffCached: true)
        )
        #expect(
            ResolveTestImpactBaselineService.resolution(from: ok(baselineSHA: "abc123", reason: nil, diffCached: nil))
                == .baseline(sha: "abc123", diffCached: false)
        )
    }

    @Test(arguments: ["no_baseline", "baseline_too_old", "no_baseline_evidence"])
    func keepsTheReasonsTheRunsRequestRecords(reason: String) {
        #expect(
            ResolveTestImpactBaselineService.resolution(from: ok(baselineSHA: nil, reason: reason, diffCached: false))
                == .unavailable(TestImpactFallbackReason(rawValue: reason))
        )
    }

    @Test(arguments: ["not_enabled", "a_reason_from_a_newer_server", nil] as [String?])
    func treatsNotEnabledAndUnknownReasonsAlike(reason: String?) {
        #expect(
            ResolveTestImpactBaselineService.resolution(from: ok(baselineSHA: nil, reason: reason, diffCached: false))
                == .notEnabled
        )
    }

    @Test func fallsBackOnAnErrorResponse() {
        #expect(
            ResolveTestImpactBaselineService.resolution(from: .notFound(.init(body: .json(.init(message: "Project not found")))))
                == .failed("Project not found")
        )
        #expect(
            ResolveTestImpactBaselineService.resolution(from: .forbidden(.init(body: .json(.init(message: "Not allowed")))))
                == .failed("Not allowed")
        )
        #expect(
            ResolveTestImpactBaselineService.resolution(from: .undocumented(statusCode: 500, .init()))
                == .failed("The test impact baseline request failed with an unknown Tuist response of 500.")
        )
    }

    @Test func abandonsARequestThatOutlastsTheTimeout() async throws {
        let result = try await withTestImpactTimeout(.milliseconds(50)) {
            try await Task.sleep(for: .seconds(10))
            return "late"
        }
        #expect(result == nil)
        #expect(try await withTestImpactTimeout(.seconds(10)) { "on time" } == "on time")
    }
}
