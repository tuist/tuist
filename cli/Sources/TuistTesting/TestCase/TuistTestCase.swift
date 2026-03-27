#if os(macOS)
    import Difference
    import FileSystem
    import Foundation
    import Logging
    import Path
    import XCTest

    import TuistSupport

    open class TuistTestCase: XCTestCase {
        fileprivate var temporaryDirectory: TemporaryDirectory!

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
        public func createFiles(_ files: [String], content: String? = nil) async throws -> [AbsolutePath] {
            let temporaryPath = try temporaryPath()
            let fileSystem = FileSystem()
            let paths = try files.map { temporaryPath.appending(try RelativePath(validating: $0)) }

            for item in paths {
                if try await !fileSystem.exists(item.parentDirectory, isDirectory: true) {
                    try await fileSystem.makeDirectory(at: item.parentDirectory)
                }
                if try await fileSystem.exists(item) {
                    try await fileSystem.remove(item)
                }
                if let content {
                    try await fileSystem.writeText(content, at: item)
                } else {
                    try await fileSystem.touch(item)
                }
            }
            return paths
        }

        @discardableResult
        public func createFolders(_ folders: [String]) async throws -> [AbsolutePath] {
            let temporaryPath = try temporaryPath()
            let fileSystem = FileSystem()
            let paths = try folders.map { temporaryPath.appending(try RelativePath(validating: $0)) }
            for path in paths {
                try await fileSystem.makeDirectory(at: path)
            }
            return paths
        }

        public func XCTAssertBetterEqual<T: Equatable>(
            _ received: @autoclosure () throws -> T,
            _ expected: @autoclosure () throws -> T,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            do {
                let expected = try expected()
                let received = try received()
                XCTAssertTrue(
                    expected == received,
                    "Found difference for \n" + diff(expected, received).joined(separator: ", "),
                    file: file,
                    line: line
                )
            } catch {
                XCTFail("Caught error while testing: \(error)", file: file, line: line)
            }
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
            let output = Logger.testingLogHandler.collected[level, comparison]

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
            let output = Logger.testingLogHandler.collected[level, comparison]

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

        public func temporaryFixture(_ pathString: String) async throws -> AbsolutePath {
            let path = try RelativePath(validating: pathString)
            let fixturePath = fixturePath(path: path)
            let destinationPath = (try temporaryPath()).appending(component: path.basename)
            try await FileSystem().copy(fixturePath, to: destinationPath)
            return destinationPath
        }
    }
#endif
