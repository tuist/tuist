import Basic
import Foundation
import XCTest

@testable import TuistCore

public class TuistTestCase: XCTestCase {
    fileprivate var temporaryDirectory: TemporaryDirectory!
    public var printer: MockPrinter!

    public override func setUp() {
        super.setUp()

        // Printer
        printer = MockPrinter()
        Printer.shared = printer
    }

    public override func tearDown() {
        // Printer
        printer = nil
        Printer.shared = Printer()

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
        let message = """
        The standard output:
        ===========
        \(printer.standardOutput)
        
        Doesn't contain the expected output:
        ===========
        \(expected)
        """
        XCTAssertTrue(printer.standardOutputMatches(with: expected), message, file: file, line: line)
    }

    public func XCTAssertPrinterErrorContains(_ expected: String, file: StaticString = #file, line: UInt = #line) {
        let message = """
        The standard error:
        ===========
        \(printer.standardError)
        
        Doesn't contain the expected output:
        ===========
        \(expected)
        """
        XCTAssertTrue(printer.standardErrorMatches(with: expected), message, file: file, line: line)
    }
}
