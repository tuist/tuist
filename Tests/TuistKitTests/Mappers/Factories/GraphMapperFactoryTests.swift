import Foundation
import TSCBasic
import TuistAutomation
import TuistCoreTesting
import TuistGraph
import TuistLoader
import XCTest
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistKit
@testable import TuistSupportTesting

final class GraphMapperFactoryTests: TuistUnitTestCase {
    var subject: GraphMapperFactory!

    override func setUp() {
        super.setUp()
        subject = GraphMapperFactory()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_default_contains_the_update_workspace_projects_graph_mapper() {
        // When
        let got = subject.default(config: .test())

        // Then
        XCTAssertContainsElementOfType(got, UpdateWorkspaceProjectsGraphMapper.self)
    }

    func test_default_contains_the_explicit_dependency_graph_mapper_when_explcit_dependencies_are_enforced() {
        // When
        let got = subject.default(
            config: .test(
                generationOptions: .test(
                    enforceExplicitDependencies: true
                )
            )
        )

        // Then
        XCTAssertContainsElementOfType(got, ExplicitDependencyGraphMapper.self)
    }

    func test_default_does_not_contain_the_explicit_dependency_graph_mapper() {
        // When
        let got = subject.default(config: .test())

        // Then
        XCTAssertDoesntContainElementOfType(got, ExplicitDependencyGraphMapper.self)
    }
}
