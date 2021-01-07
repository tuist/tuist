import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLinting
@testable import TuistLintingTesting
@testable import TuistSupportTesting

final class CodeLinterTests: TuistUnitTestCase {
    private var rootDirectoryLocator: MockRootDirectoryLocator!
    private var binaryLocator: MockBinaryLocator!

    private var subject: CodeLinter!

    override func setUp() {
        super.setUp()

        rootDirectoryLocator = MockRootDirectoryLocator()
        binaryLocator = MockBinaryLocator()

        subject = CodeLinter(rootDirectoryLocator: rootDirectoryLocator,
                             binaryLocator: binaryLocator)
    }

    override func tearDown() {
        subject = nil

        rootDirectoryLocator = nil
        binaryLocator = nil

        super.tearDown()
    }

    func test_lint_throws_an_error_when_binary_no_found() {
        // Given
        let fakeError = TestError("binaryNotFound")
        let fakeSources = [
            AbsolutePath("/xyz/abc"),
            AbsolutePath("/xyz/def"),
            AbsolutePath("/xyz/hij"),
        ]

        let fakePath = AbsolutePath("/foo/bar")
        binaryLocator.stubbedSwiftLintPathError = fakeError

        // When
        XCTAssertThrowsSpecific(try subject.lint(sources: fakeSources, path: fakePath), fakeError)
    }

    func test_lint_no_configuration() throws {
        // Given
        let fakeSources = [
            AbsolutePath("/xyz/abc"),
            AbsolutePath("/xyz/def"),
            AbsolutePath("/xyz/hij"),
        ]
        let fakePath = AbsolutePath("/foo/bar")
        binaryLocator.stubbedSwiftLintPathResult = "/swiftlint"
        system.succeedCommand(binaryLocator.stubbedSwiftLintPathResult.pathString,
                              "lint",
                              "--use-script-input-files")

        // When
        try subject.lint(sources: fakeSources, path: fakePath)
    }

    func test_lint_with_configuration_yml() throws {
        // Given
        let fakeSources = [
            AbsolutePath("/xyz/abc"),
            AbsolutePath("/xyz/def"),
            AbsolutePath("/xyz/hij"),
        ]
        let fakePath = AbsolutePath("/foo/bar")
        let fakeRoot = AbsolutePath("/root")
        let fakeSwiftLintPath = AbsolutePath("/swiftlint")
        let swiftLintConfigPath = fakeRoot.appending(RelativePath("\(Constants.tuistDirectoryName)/.swiftlint.yml"))

        rootDirectoryLocator.locateStub = fakeRoot
        binaryLocator.stubbedSwiftLintPathResult = fakeSwiftLintPath
        fileHandler.stubExists = { $0 == swiftLintConfigPath }

        system.env = [
            "SCRIPT_INPUT_FILE_COUNT": "3",
            "SCRIPT_INPUT_FILE_0": fakeSources[0].pathString,
            "SCRIPT_INPUT_FILE_1": fakeSources[1].pathString,
            "SCRIPT_INPUT_FILE_2": fakeSources[2].pathString,
        ]
        system.succeedCommand(binaryLocator.stubbedSwiftLintPathResult.pathString,
                              "lint",
                              "--use-script-input-files",
                              "--config",
                              swiftLintConfigPath.pathString)

        // When
        try subject.lint(sources: fakeSources, path: fakePath)
    }

    func test_lint_with_configuration_yaml() throws {
        // Given
        let fakeSources = [
            AbsolutePath("/xyz/abc"),
            AbsolutePath("/xyz/def"),
            AbsolutePath("/xyz/hij"),
        ]
        let fakePath = AbsolutePath("/foo/bar")
        let fakeRoot = AbsolutePath("/root")
        let fakeSwiftLintPath = AbsolutePath("/swiftlint")
        let swiftLintConfigPath = fakeRoot.appending(RelativePath("\(Constants.tuistDirectoryName)/.swiftlint.yaml"))

        rootDirectoryLocator.locateStub = fakeRoot
        binaryLocator.stubbedSwiftLintPathResult = fakeSwiftLintPath
        fileHandler.stubExists = { $0 == swiftLintConfigPath }
        system.succeedCommand(binaryLocator.stubbedSwiftLintPathResult.pathString,
                              "lint",
                              "--use-script-input-files",
                              "--config",
                              swiftLintConfigPath.pathString)

        // When
        try subject.lint(sources: fakeSources, path: fakePath)
    }
}
