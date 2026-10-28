import Foundation
import Path
import Testing
import XCTest
@testable import XcodeGraph

final class TestPlanTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = TestPlan(
            path: try AbsolutePath(validating: "/path/to"),
            testTargets: [],
            isDefault: true
        )

        // Then
        XCTAssertCodable(subject)
    }
}

struct TestPlanCompatibilityTests {
    @Test func decodes_legacy_graph_without_coverage_fields() throws {
        let data = Data(
            #"{"name":"Legacy","path":"/tmp/Legacy.xctestplan","testTargets":[],"isDefault":true,"kind":"generated"}"#.utf8
        )
        let plan = try JSONDecoder().decode(TestPlan.self, from: data)
        let factory: (AbsolutePath, [TestableTarget], Bool, TestPlan.Kind) -> TestPlan = TestPlan.init
        #expect(plan == factory(try AbsolutePath(validating: "/tmp/Legacy.xctestplan"), [], true, .generated))
        #expect(plan.coverage == nil)
        #expect(plan.codeCoverageTargets.isEmpty)
    }
}
