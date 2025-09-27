import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistAutomation
@testable import TuistTesting

final class SkipUnitTestsProjectMapperTests: TuistUnitTestCase {
    private var subject: SkipUnitTestsProjectMapper!

    override func setUp() {
        super.setUp()
        subject = .init()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_prune_is_set_to_unit_targets() throws {
        // Given
        let project = Project.test(
            targets: [
                .test(name: "App", product: .app),
                .test(name: "UnitTests", product: .unitTests),
                .test(name: "UITests", product: .uiTests),
            ]
        )

        // When
        let (gotProject, gotSideEffects) = try subject.map(project: project)
        XCTAssertEqual(
            gotProject,
            Project.test(
                targets: [
                    .test(name: "App", product: .app),
                    .test(
                        name: "UnitTests",
                        product: .unitTests,
                        prune: true,
                        metadata: .metadata(tags: ["tuist:prunable"])
                    ),
                    .test(name: "UITests", product: .uiTests),
                ]
            )
        )
        XCTAssertEmpty(gotSideEffects)
    }
}
