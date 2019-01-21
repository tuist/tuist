@testable import TuistKit
import XCTest
import Basic
@testable import TuistCoreTesting

final class SetupLoaderTests: XCTestCase {

    var subject: SetupLoader!
    var upLinter: MockUpLinter!
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!
    var graphManifestLoader: MockGraphManifestLoader!
    var system: MockSystem!

    override func setUp() {
        super.setUp()

        upLinter = MockUpLinter()
        fileHandler = try! MockFileHandler()
        printer = MockPrinter()
        graphManifestLoader = MockGraphManifestLoader()
        system = MockSystem()
        subject = SetupLoader(upLinter: upLinter,
                          fileHandler: fileHandler,
                          printer: printer,
                          graphManifestLoader: graphManifestLoader,
                          system: system)
    }

    func test_meet_when_no_actions() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        var receivedPaths = [String]()
        graphManifestLoader.loadSetupStub = { gotPath in
            receivedPaths.append(gotPath.asString)
            return []
        }

        // when / then
        XCTAssertNoThrow(try subject.meet(at: projectPath))

        XCTAssertEqual(receivedPaths, ["/test/test1"])
        XCTAssertEqual(upLinter.lintCount, 0)
        XCTAssertEqual(printer.standardOutput, "")
        XCTAssertEqual(printer.standardError, "")
    }

    func test_meet_when_actions_provided() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        let mockUp1 = MockUp(name: "1")
        mockUp1.isMetStub = { _, _ in return true }
        let mockUp2 = MockUp(name: "2")
        mockUp2.isMetStub = { _, _ in return false }
        var receivedUp = [Upping]()
        upLinter.lintStub = { up in receivedUp.append(up); return [] }
        graphManifestLoader.loadSetupStub = { _ in [mockUp1, mockUp2] }

        // when / then
        XCTAssertNoThrow(try subject.meet(at: projectPath))

        XCTAssertEqual(mockUp1.meetCallCount, 0)
        XCTAssertEqual(mockUp2.meetCallCount, 1)
        XCTAssertEqual(upLinter.lintCount, 2)
        XCTAssertEqual(receivedUp.count, 2)
        XCTAssertTrue(mockUp1 === receivedUp[0])
        XCTAssertTrue(mockUp2 === receivedUp[1])
        XCTAssertEqual(printer.standardOutput, "Configuring 2\n")
        XCTAssertEqual(printer.standardError, "")
    }

    func test_meet_when_loadSetup_throws() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        graphManifestLoader.loadSetupStub = { path in throw GraphManifestLoaderError.setupNotFound(path) }

        // when / then
        XCTAssertThrowsError(try subject.meet(at: projectPath)) { error in
            XCTAssertEqual(error as? GraphManifestLoaderError, GraphManifestLoaderError.setupNotFound(projectPath))
        }
    }
}
