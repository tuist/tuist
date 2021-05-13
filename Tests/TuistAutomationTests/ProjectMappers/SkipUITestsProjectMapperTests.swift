import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class SkipUITestsProjectMapperTests: TuistUnitTestCase {
    private var subject: SkipUITestsProjectMapper!

    override func setUp() {
        super.setUp()
        subject = .init()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_prune_is_set_to_ui_targets() throws {
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
                    .test(name: "UnitTests", product: .unitTests),
                    .test(name: "UITests", product: .uiTests, prune: true),
                ]
            )
        )
        XCTAssertEmpty(gotSideEffects)
    }
}
