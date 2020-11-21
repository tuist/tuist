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
    private var contentHasher: MockContentHasher!

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = .init(
            contentHasher: contentHasher
        )
    }

    override func tearDown() {
        super.tearDown()
        contentHasher = nil
        subject = nil
    }

    func test_map() throws {
        // Given
        let projectPath = try temporaryPath()
        contentHasher.hashStub = { _ in
            projectPath.basename
        }
        let xcodeProjPath = projectPath.appending(component: "A.xcodeproj")
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath,
            name: "A"
        )
        let projectsDirectory = environment.projectsCacheDirectory
            .appending(component: "A-\(projectPath.basename)")

        // When
        let (gotProject, gotSideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(
            gotProject,
            Project.test(
                path: projectPath,
                xcodeProjPath: projectsDirectory.appending(component: "A.xcodeproj"),
                name: "A"
            )
        )
        XCTAssertEqual(
            gotSideEffects,
            [
                .directory(
                    DirectoryDescriptor(
                        path: projectsDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
