import Foundation
import TSCBasic
import TuistAutomation
import TuistCoreTesting
import TuistGraph
import TuistLoader
import TuistSigning
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
        let got = subject.default()

        // Then
        XCTAssertContainsElementOfType(got, UpdateWorkspaceProjectsGraphMapper.self)
    }
}
