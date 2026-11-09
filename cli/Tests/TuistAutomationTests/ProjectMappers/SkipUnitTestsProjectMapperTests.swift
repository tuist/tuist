import Foundation
import Testing
import TSCBasic
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistAutomation
@testable import TuistTesting

struct SkipUnitTestsProjectMapperTests {
    private var subject: SkipUnitTestsProjectMapper!

    init() throws {
        subject = SkipUnitTestsProjectMapper()
    }

    @Test func prune_is_set_to_unit_targets() throws {
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

        // Then
        #expect(
            gotProject == Project.test(
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
        #expect(gotSideEffects.isEmpty)
    }
}
