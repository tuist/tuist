import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

final class CarthageControllerTests: XCTestCase {
    var system: MockSystem!
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!
    var subject: CarthageController!
    var graph: MockGraph!
    var frameworkNode: FrameworkNode!
    var cartfilePath: AbsolutePath!
    var frameworkPath: AbsolutePath!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        fileHandler = try! MockFileHandler()
        printer = MockPrinter()

        cartfilePath = fileHandler.currentPath.appending(components: "Cartfile")
        frameworkPath = fileHandler.currentPath.appending(components: "Carthage", "Build", "iOS", "Test.framework")

        try! fileHandler.touch(cartfilePath)
        frameworkNode = FrameworkNode(path: frameworkPath)

        graph = MockGraph(entryPath: fileHandler.currentPath,
                          precompiledNodes: [frameworkNode])
        subject = CarthageController(system: system,
                                     fileHandler: fileHandler,
                                     printer: printer)
    }

    func test_updateIfNecessary() throws {
        system.stub(args: ["which", "carthage"],
                    stderror: nil,
                    stdout: "/bin/carthage",
                    exitstatus: 0)
        system.stub(args: ["/bin/carthage", "--project-directory", fileHandler.currentPath.asString],
                    stderror: nil,
                    stdout: "output",
                    exitstatus: 0)

        try subject.updateIfNecessary(graph: graph)

        XCTAssertEqual(printer.printArgs.first, "The following Carthage dependencies need to be pulled:\n - \(frameworkPath.asString)")
        XCTAssertEqual(printer.printArgs.last, "Updating Carthage dependencies at \(fileHandler.currentPath.asString)")
    }

    func test_updateIfNecessary_throws_when_carthage_cannot_be_found() throws {
        system.stub(args: ["which", "carthage"],
                    stderror: "carthage not found",
                    stdout: nil,
                    exitstatus: 1)

        XCTAssertThrowsError(try subject.updateIfNecessary(graph: graph)) {
            XCTAssertEqual($0 as? CarthageError, .notFound)
        }
    }

    func test_updateIfNecessary_throws_when_carthage_update_fails() throws {
        system.stub(args: ["which", "carthage"],
                    stderror: nil,
                    stdout: "/bin/carthage",
                    exitstatus: 0)
        system.stub(args: ["/bin/carthage", "--project-directory", fileHandler.currentPath.asString],
                    stderror: "it failed",
                    stdout: nil,
                    exitstatus: 1)

        XCTAssertThrowsError(try subject.updateIfNecessary(graph: graph)) {
            XCTAssertEqual($0 as? SystemError, SystemError(stderror: "it failed",
                                                           exitcode: 1))
        }
    }
}
