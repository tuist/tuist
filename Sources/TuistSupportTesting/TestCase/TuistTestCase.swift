import Basic
import Foundation
import XCTest

@testable import TuistSupport

// This mock file handler is used to override both, the current path and the temporary directory
// returned by the inTemporaryDirectory method. The temporary directory is lazily created if either
// the test case or subject consume the API.
private class MockFileHandler: FileHandler {
    let temporaryDirectory: () throws -> (AbsolutePath)

    init(temporaryDirectory: @escaping () throws -> (AbsolutePath)) {
        self.temporaryDirectory = temporaryDirectory
        super.init()
    }

    // swiftlint:disable:next force_try
    override var currentPath: AbsolutePath { try! self.temporaryDirectory() }

    override func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws {
        try closure(temporaryDirectory())
    }
}

public class TuistTestCase: XCTestCase {
    fileprivate var temporaryDirectory: TemporaryDirectory!
    
    var collectedLogs: [String] = [ ]
        
    public override static func setUp() {
        super.setUp()
        DispatchQueue.once(token: "io.tuist.test.logging") {
            LoggingSystem.bootstrap(TestingLogHandler.init)
        }
    }

    public override func setUp() {
        super.setUp()

        // FileHandler
        FileHandler.shared = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })
    }

    public override func tearDown() {
        
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
        let fileHandler = FileHandler()
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

    public func XCTAssertPrinterContains(_ expected: String, at level: Logger.Level, _ comparison: (Logger.Level, Logger.Level) -> Bool, file: StaticString = #file, line: UInt = #line) {
        
        let standardError = TestingLogHandler.collected[level, comparison]
        
        let message = """
        The standard error:
        ===========
        \(standardError)
        
        Doesn't contain the expected output:
        ===========
        \(expected)
        """
        
        XCTAssertTrue(standardError.contains(expected), message, file: file, line: line)
    }

    public func temporaryFixture(_ pathString: String) throws -> AbsolutePath {
        let path = RelativePath(pathString)
        let fixturePath = self.fixturePath(path: path)
        let destinationPath = (try temporaryPath()).appending(component: path.basename)
        try FileHandler.shared.copy(from: fixturePath, to: destinationPath)
        return destinationPath
    }
}

