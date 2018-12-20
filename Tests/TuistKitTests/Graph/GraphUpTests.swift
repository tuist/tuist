import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

final class GraphUpTests: XCTestCase {
    var printer: MockPrinter!
    var system: System!
    var subject: GraphUp!
    var graphCache: GraphLoaderCache!
    var graph: Graph!
    var fileHandler: MockFileHandler!
    var up: MockUp!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        system = System()
        fileHandler = try! MockFileHandler()
        graphCache = GraphLoaderCache()
        graph = Graph.test(cache: graphCache)
        up = MockUp(name: "GraphUpTests")
        graphCache.projects[fileHandler.currentPath] = Project.test(up: [up])
        subject = GraphUp(printer: printer,
                          system: system)
    }

    func test_meet_when_there_are_not_met_ups() throws {
        up.isMetStub = { _, _ in false }

        try subject.meet(graph: graph)

        XCTAssertStandardOutput(printer, pattern: """
        Setting up environment for project at /test
        Configuring GraphUpTests
        """)
        XCTAssertEqual(up.meetCallCount, 1)
    }

    func test_meet_when_ups_are_met() throws {
        up.isMetStub = { _, _ in true }

        try subject.meet(graph: graph)

        XCTAssertStandardOutput(printer, pattern: """
        Setting up environment for project at /test
        """)
        XCTAssertEqual(up.meetCallCount, 0)
    }

    func test_isMet_returnsTrueWhenAnyCommandIsNotMet() throws {
        XCTAssertFalse(try subject.isMet(graph: graph))
    }
}
