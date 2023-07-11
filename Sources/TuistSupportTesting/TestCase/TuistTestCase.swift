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

    public var stubContentsOfDirectory: ((AbsolutePath) throws -> [AbsolutePath])?
    override public func contentsOfDirectory(_ path: AbsolutePath) throws -> [AbsolutePath] {
        guard let stubContentsOfDirectory = stubContentsOfDirectory else {
            return try super.contentsOfDirectory(path)
        }
        return try stubContentsOfDirectory(path)
    }

    public var stubFilesAndDirectoriesContained: ((AbsolutePath) -> [AbsolutePath]?)?
    override public func filesAndDirectoriesContained(in path: AbsolutePath) -> [AbsolutePath]? {
        guard let stubFilesAndDirectoriesContained = stubFilesAndDirectoriesContained else {
            return super.filesAndDirectoriesContained(in: path)
        }
        return stubFilesAndDirectoriesContained(path)
    }

    public var stubExists: ((AbsolutePath) -> Bool)?
    override public func exists(_ path: AbsolutePath) -> Bool {
        guard let stubExists = stubExists else {
            return super.exists(path)
        }
        return stubExists(path)
    }

    public var stubReadFile: ((AbsolutePath) throws -> Data)?
    override public func readFile(_ path: AbsolutePath) throws -> Data {
        guard let stubReadFile = stubReadFile else {
            return try super.readFile(path)
        }
        return try stubReadFile(path)
    }

    public var stubWrite: ((String, AbsolutePath, Bool) throws -> Void)?
    override public func write(_ content: String, path: AbsolutePath, atomically: Bool) throws {
        guard let stubWrite = stubWrite else {
            return try super.write(content, path: path, atomically: atomically)
        }
        return try stubWrite(content, path, atomically)
    }

    public var stubIsFolder: ((AbsolutePath) -> Bool)?
    override public func isFolder(_ path: AbsolutePath) -> Bool {
        guard let stubIsFolder = stubIsFolder else {
            return super.isFolder(path)
        }
        return stubIsFolder(path)
    }

    override public func inTemporaryDirectory<Result>(
        removeOnCompletion _: Bool,
        _ closure: (AbsolutePath) throws -> Result
    ) throws -> Result {
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

    public var stubGlob: ((AbsolutePath, String) -> [AbsolutePath])?
    override public func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        guard let stubGlob = stubGlob else {
            return super.glob(path, glob: glob)
        }
        return stubGlob(path, glob)
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

    public var environment: MockEnvironment!
    public var fileHandler: MockFileHandler!

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
        TestingLogHandler.reset()
        super.tearDown()
    }

    public func temporaryPath() throws -> AbsolutePath {
        if temporaryDirectory == nil {
            temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        }
        return temporaryDirectory.path
    }

    @discardableResult
    public func createFiles(_ files: [String], content: String? = nil) throws -> [AbsolutePath] {
        let temporaryPath = try temporaryPath()
        let fileHandler = FileHandler()
        let paths = files.map { temporaryPath.appending(RelativePath($0)) }

        try paths.forEach {
            try fileHandler.touch($0)
            if let content = content {
                try fileHandler.write(content, path: $0, atomically: true)
            }
        }
        return paths
    }

    @discardableResult
    public func createFolders(_ folders: [String]) throws -> [AbsolutePath] {
        let temporaryPath = try temporaryPath()
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

    public func XCTAssertPrinterOutputNotContains(_ notExpected: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertPrinterNotContains(notExpected, at: .warning, >=, file: file, line: line)
    }

    public func XCTAssertPrinterErrorContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertPrinterContains(expected, at: .error, <=, file: file, line: line)
    }

    public func XCTAssertPrinterErrorNotContains(_ notExpected: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertPrinterNotContains(notExpected, at: .error, <=, file: file, line: line)
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

    /// Asserts that a directory at given path contains expected elements.
    /// It does not check the contents of a directory recursively.
    /// - Throws: An error if the directory at given path does not exist.
    public func XCTAssertDirectoryContentEqual(
        _ directory: AbsolutePath,
        _ expected: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let directoryContent = try fileHandler
            .contentsOfDirectory(directory)
            .map(\.pathString)
            .sorted()

        let expectedContent = expected
            .map { directory.appending(RelativePath($0)) }
            .map(\.pathString)
            .sorted()

        let message = """
        The directory content:
        ===========
        \(directoryContent.isEmpty ? "<Empty>" : directoryContent.joined(separator: "\n"))

        Doesn't equal to expected:
        ===========
        \(expectedContent.isEmpty ? "<Empty>" : expectedContent.joined(separator: "\n"))
        """

        XCTAssertEqual(directoryContent, expectedContent, message, file: file, line: line)
    }

    public func temporaryFixture(_ pathString: String) throws -> AbsolutePath {
        let path = RelativePath(pathString)
        let fixturePath = fixturePath(path: path)
        let destinationPath = (try temporaryPath()).appending(component: path.basename)
        try FileHandler.shared.copy(from: fixturePath, to: destinationPath)
        return destinationPath
    }
}
