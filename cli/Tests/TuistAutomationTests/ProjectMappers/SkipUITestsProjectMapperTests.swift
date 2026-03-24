import Foundation
import Testing
import TSCBasic
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistAutomation
@testable import TuistTesting

struct SkipUITestsProjectMapperTests {
    private let subject: SkipUITestsProjectMapper
    init() {
        subject = .init()
    }

    @Test
    func prune_is_set_to_ui_targets() throws {
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
        #expect(gotProject == Project.test(
            targets: [
                .test(name: "App", product: .app),
                .test(name: "UnitTests", product: .unitTests),
                .test(name: "UITests", product: .uiTests, prune: true),
            ]
        ))
        #expect(gotSideEffects.isEmpty)
    }
}
