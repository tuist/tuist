import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

public final class DeleteDerivedDirectoryProjectMapperTests: TuistUnitTestCase {
    var subject: DeleteDerivedDirectoryProjectMapper!

    public override func setUp() {
        super.setUp()
        subject = DeleteDerivedDirectoryProjectMapper()
    }

    public override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map_returns_sideEffectsToDeleteDerivedDirectories() throws {
        // Given
        let projectA = Project.test(path: "/projectA")

        // When
        let (_, sideEffects) = try subject.map(project: projectA)

        // Then
        XCTAssertEqual(sideEffects, [
            .directory(.init(path: projectA.path.appending(component: Constants.DerivedDirectory.name), state: .absent)),
        ])
    }
}
