import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class AutomationPathProjectMapperTests: TuistUnitTestCase {
    private var subject: AutomationPathProjectMapper!
    private var xcodeProjDirectory: AbsolutePath!

    override func setUpWithError() throws {
        try super.setUpWithError()
        xcodeProjDirectory = try temporaryPath()
        subject = .init(
            xcodeProjDirectory: xcodeProjDirectory
        )
    }

    override func tearDown() {
        xcodeProjDirectory = nil
        subject = nil
        super.tearDown()
    }

    func test_map() throws {
        // Given
        let projectPath: AbsolutePath = xcodeProjDirectory
        let xcodeProjPath = projectPath.appending(component: "A.xcodeproj")
        let project = Project.test(
            path: projectPath,
            sourceRootPath: xcodeProjDirectory,
            xcodeProjPath: xcodeProjPath,
            name: "A"
        )

        // When
        let (gotProject, gotSideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(
            gotProject,
            Project.test(
                path: projectPath,
                sourceRootPath: xcodeProjDirectory,
                xcodeProjPath: projectPath.appending(component: "A.xcodeproj"),
                name: "A"
            )
        )
        XCTAssertEqual(
            gotSideEffects,
            [
                .directory(
                    DirectoryDescriptor(
                        path: xcodeProjDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
