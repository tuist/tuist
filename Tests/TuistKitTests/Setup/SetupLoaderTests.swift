import Basic
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

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
        mockUp1.isMetStub = { _, _ in true }
        let mockUp2 = MockUp(name: "2")
        mockUp2.isMetStub = { _, _ in false }
        var lintedUps = [Upping]()
        upLinter.lintStub = { up in lintedUps.append(up); return [] }
        graphManifestLoader.loadSetupStub = { _ in [mockUp1, mockUp2] }

        // when / then
        XCTAssertNoThrow(try subject.meet(at: projectPath))

        XCTAssertEqual(mockUp1.meetCallCount, 0)
        XCTAssertEqual(mockUp2.meetCallCount, 1)
        XCTAssertEqual(upLinter.lintCount, 2)
        XCTAssertEqual(lintedUps.count, 2)
        XCTAssertTrue(mockUp1 === lintedUps[0])
        XCTAssertTrue(mockUp2 === lintedUps[1])
        XCTAssertEqual(printer.standardOutput, "Configuring 2\n")
        XCTAssertEqual(printer.standardError, "")
    }

    func test_meet_when_loadSetup_throws() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        graphManifestLoader.loadSetupStub = { path in throw GraphManifestLoaderError.manifestNotFound(.setup, projectPath) }

        // when / then
        XCTAssertThrowsError(try subject.meet(at: projectPath)) { error in
            XCTAssertEqual(error as? GraphManifestLoaderError, GraphManifestLoaderError.manifestNotFound(.setup, projectPath))
        }
    }

    func test_meet_when_actions_provided_then_lint_all_before_meet() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        let mockUp1 = MockUp(name: "1")
        mockUp1.isMetStub = { _, _ in false }
        let mockUp2 = MockUp(name: "2")
        mockUp2.isMetStub = { _, _ in false }
        let mockUp3 = MockUp(name: "3")
        mockUp3.isMetStub = { _, _ in false }
        let mockUp4 = MockUp(name: "4")
        mockUp4.isMetStub = { _, _ in false }
        let mockUps = [mockUp1, mockUp2, mockUp3, mockUp4]
        var lintedUps = [Upping]()
        upLinter.lintStub = { up in
            lintedUps.append(up)
            if up === mockUp1 {
                return [LintingIssue(reason: "mockup1 error", severity: .error)]
            }
            if up === mockUp2 {
                return [LintingIssue(reason: "mockup2 warning", severity: .warning)]
            }
            if up === mockUp3 {
                return [LintingIssue(reason: "mockup3 error", severity: .error)]
            }
            return []
        }
        graphManifestLoader.loadSetupStub = { _ in mockUps }

        // when / then
        XCTAssertThrowsError(try subject.meet(at: projectPath)) { error in
            XCTAssertEqual(error as? LintingError, LintingError())
        }

        XCTAssertEqual(mockUps.map { $0.meetCallCount }, Array(repeating: 0, count: mockUps.count))
        XCTAssertEqual(mockUps.map { $0.isMetCallCount }, Array(repeating: 0, count: mockUps.count))
        XCTAssertEqual(lintedUps.count, mockUps.count)

        let expectedOutput = """
        The following issues have been found:
          - mockup2 warning
        The following critical issues have been found:
          - mockup1 error
          - mockup3 error
        """
        XCTAssertEqual(printer.standardOutput, expectedOutput)
        XCTAssertEqual(printer.standardError, "")
    }
}
