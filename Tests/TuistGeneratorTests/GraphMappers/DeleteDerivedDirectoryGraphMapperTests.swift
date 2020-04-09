import Basic
import Foundation
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

public final class DeleteDerivedDirectoryGraphMapperTests: TuistUnitTestCase {
    var subject: DeleteDerivedDirectoryGraphMapper!

    public override func setUp() {
        super.setUp()
        subject = DeleteDerivedDirectoryGraphMapper()
    }

    public override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map_returns_sideEffectsToDeleteDerivedDirectories() throws {
        // Given
        let projectA = Project.test(path: "/projectA")
        let projectB = Project.test(path: "/projectB")
        let graph = Graph.test(projects: [projectA, projectB])

        // When
        let (_, sideEffects) = try subject.map(graph: graph)

        // Let
        let expected: [SideEffectDescriptor] = [
            .directory(.init(path: projectA.path.appending(component: Constants.DerivedFolder.name), state: .absent)),
            .directory(.init(path: projectB.path.appending(component: Constants.DerivedFolder.name), state: .absent)),
        ]
        XCTAssertEqual(sideEffects, Set(expected))
    }
}
