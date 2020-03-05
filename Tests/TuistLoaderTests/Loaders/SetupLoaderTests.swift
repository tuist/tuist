import Basic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class SetupLoaderTests: TuistUnitTestCase {
    var subject: SetupLoader!
    var upLinter: MockUpLinter!
    var manifestLoader: MockManifestLoader!

    override func setUp() {
        super.setUp()
        upLinter = MockUpLinter()
        manifestLoader = MockManifestLoader()
        subject = SetupLoader(upLinter: upLinter, manifestLoader: manifestLoader)
    }

    override func tearDown() {
        upLinter = nil
        manifestLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_meet_when_no_actions() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        var receivedPaths = [String]()
        manifestLoader.loadSetupStub = { gotPath in
            receivedPaths.append(gotPath.pathString)
            return []
        }

        // when / then
        XCTAssertNoThrow(try subject.meet(at: projectPath))

        XCTAssertEqual(receivedPaths, ["/test/test1"])
        XCTAssertEqual(upLinter.lintCount, 0)
    }

    func test_meet_when_actions_provided() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        let mockUp1 = MockUp(name: "1")
        mockUp1.isMetStub = { _ in true }
        let mockUp2 = MockUp(name: "2")
        mockUp2.isMetStub = { _ in false }
        var lintedUps = [Upping]()
        upLinter.lintStub = { up in lintedUps.append(up); return [] }
        manifestLoader.loadSetupStub = { _ in [mockUp1, mockUp2] }

        // when / then
        XCTAssertNoThrow(try subject.meet(at: projectPath))

        XCTAssertEqual(mockUp1.meetCallCount, 0)
        XCTAssertEqual(mockUp2.meetCallCount, 1)
        XCTAssertEqual(upLinter.lintCount, 2)
        XCTAssertEqual(lintedUps.count, 2)
        XCTAssertTrue(mockUp1 === lintedUps[0])
        XCTAssertTrue(mockUp2 === lintedUps[1])
        XCTAssertPrinterOutputContains("Configuring 2")
    }

    func test_meet_when_loadSetup_throws() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        manifestLoader.loadSetupStub = { _ in throw ManifestLoaderError.manifestNotFound(.setup, projectPath) }

        // when / then
        XCTAssertThrowsSpecific(try subject.meet(at: projectPath),
                                ManifestLoaderError.manifestNotFound(.setup, projectPath))
    }

    func test_meet_when_actions_provided_then_lint_all_before_meet() {
        // given
        let projectPath = AbsolutePath("/test/test1")
        let mockUp1 = MockUp(name: "1")
        mockUp1.isMetStub = { _ in false }
        let mockUp2 = MockUp(name: "2")
        mockUp2.isMetStub = { _ in false }
        let mockUp3 = MockUp(name: "3")
        mockUp3.isMetStub = { _ in false }
        let mockUp4 = MockUp(name: "4")
        mockUp4.isMetStub = { _ in false }
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
        manifestLoader.loadSetupStub = { _ in mockUps }

        // when / then
        XCTAssertThrowsSpecific(try subject.meet(at: projectPath),
                                LintingError())

        XCTAssertEqual(mockUps.map { $0.meetCallCount }, Array(repeating: 0, count: mockUps.count))
        XCTAssertEqual(mockUps.map { $0.isMetCallCount }, Array(repeating: 0, count: mockUps.count))
        XCTAssertEqual(lintedUps.count, mockUps.count)

        let expectedOutput = """
        mockup2 warning
        """
        let expectedError = """
        mockup1 error
        mockup3 error
        """
        XCTAssertPrinterOutputContains(expectedOutput)
        XCTAssertPrinterErrorContains(expectedError)
    }
}
