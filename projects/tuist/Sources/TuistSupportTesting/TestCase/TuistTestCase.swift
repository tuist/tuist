import Foundation
import TSCBasic
import XCTest

@testable import TuistSupport

// This mock file handler is used to override the current path to a temporary directory.
// The temporary directory is lazily created if either the test case or subject consume the API.
public final class MockFileHandler: FileHandler {
    let temporaryDirectory: () throws -> (AbsolutePath)

    init(temporaryDirectory: @escaping () throws -> (AbsolutePath)) {
        self.temporaryDirectory = temporaryDirectory
        super.init()
    }

    public var homeDirectoryStub: AbsolutePath?
    public var cacheDirectoryStub: AbsolutePath?

    // swiftlint:disable:next force_try
    override public var homeDirectory: AbsolutePath { homeDirectoryStub ?? (try! temporaryDirectory()) }

    // swiftlint:disable:next force_try
    override public var currentPath: AbsolutePath { try! temporaryDirectory() }

    public var stubExists: ((AbsolutePath) -> Bool)?
    override public func exists(_ path: AbsolutePath) -> Bool {
        guard let stubExists = stubExists else {
            return super.exists(path)
        }
        return stubExists(path)
    }

    override public func inTemporaryDirectory<Result>(removeOnCompletion _: Bool, _ closure: (AbsolutePath) throws -> Result) throws -> Result {
        try closure(temporaryDirectory())
    }

    override public func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws {
        try closure(temporaryDirectory())
    }

    override public func inTemporaryDirectory(removeOnCompletion _: Bool, _ closure: (AbsolutePath) throws -> Void) throws {
        try closure(temporaryDirectory())
    }

    override public func inTemporaryDirectory<Result>(_ closure: (AbsolutePath) throws -> Result) throws -> Result {
        try closure(temporaryDirectory())
    }
}

open class TuistTestCase: XCTestCase {
    fileprivate var temporaryDirectory: TemporaryDirectory!

    override public static func setUp() {
        super.setUp()
        DispatchQueue.once(token: "io.tuist.test.logging") {
            LoggingSystem.bootstrap(TestingLogHandler.init)
        }
    }

    public var fileHandler: MockFileHandler!
    public var environment: MockEnvironment!

    override open func setUp() {
        super.setUp()

        do {
            // Environment
            environment = try MockEnvironment()
            Environment.shared = environment
        } catch {
            XCTFail("Failed to setup environment")
        }

        // FileHandler
        fileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })
        FileHandler.shared = fileHandler
    }

    override open func tearDown() {
        temporaryDirectory = nil
        super.tearDown()
    }

    public func temporaryPath() throws -> AbsolutePath {
        if temporaryDirectory == nil {
            temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        }
        return temporaryDirectory.path
    }

    @discardableResult
    public func createFiles(_ files: [String]) throws -> [AbsolutePath] {
        let temporaryPath = try self.temporaryPath()
        let fileHandler = FileHandler()
        let paths = files.map { temporaryPath.appending(RelativePath($0)) }

        try paths.forEach {
            try fileHandler.touch($0)
        }
        return paths
    }

    @discardableResult
    public func createFolders(_ folders: [String]) throws -> [AbsolutePath] {
        let temporaryPath = try self.temporaryPath()
        let fileHandler = FileHandler.shared
        let paths = folders.map { temporaryPath.appending(RelativePath($0)) }
        try paths.forEach {
            try fileHandler.createFolder($0)
        }
        return paths
    }

    public func XCTAssertPrinterOutputContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertPrinterContains(expected, at: .warning, >=, file: file, line: line)
    }

    public func XCTAssertPrinterErrorContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertPrinterContains(expected, at: .error, <=, file: file, line: line)
    }

    public func XCTAssertPrinterContains(
        _ expected: String,
        at level: Logger.Level,
        _ comparison: (Logger.Level, Logger.Level) -> Bool,
        file: StaticString = #file, line: UInt = #line
    ) {
        let output = TestingLogHandler.collected[level, comparison]

        let message = """
        The output:
        ===========
        \(output)

        Doesn't contain the expected:
        ===========
        \(expected)
        """

        XCTAssertTrue(output.contains(expected), message, file: file, line: line)
    }

    public func XCTAssertPrinterNotContains(
        _ notExpected: String,
        at level: Logger.Level,
        _ comparison: (Logger.Level, Logger.Level) -> Bool,
        file: StaticString = #file, line: UInt = #line
    ) {
        let output = TestingLogHandler.collected[level, comparison]

        let message = """
        The output:
        ===========
        \(output)

        Contains the not expected:
        ===========
        \(notExpected)
        """

        XCTAssertFalse(output.contains(notExpected), message, file: file, line: line)
    }

    public func temporaryFixture(_ pathString: String) throws -> AbsolutePath {
        let path = RelativePath(pathString)
        let fixturePath = self.fixturePath(path: path)
        let destinationPath = (try temporaryPath()).appending(component: path.basename)
        try FileHandler.shared.copy(from: fixturePath, to: destinationPath)
        return destinationPath
    }
}
