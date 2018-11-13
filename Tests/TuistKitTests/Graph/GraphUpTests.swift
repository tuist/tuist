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

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        system = System()
        fileHandler = try! MockFileHandler()
        graphCache = GraphLoaderCache()
        graph = Graph.test(cache: graphCache)
        subject = GraphUp(printer: printer,
                          system: system)
    }

    func test_isMet_returnsTrueWhenAnyCommandIsNotMet() throws {
        graphCache.projects[fileHandler.currentPath] = Project.test(up: [
            CustomCommand(name: "invalid",
                          meet: ["install", "invalid"],
                          isMet: ["which invalid"]),
        ])
        XCTAssertFalse(try subject.isMet(graph: graph))
    }
}
