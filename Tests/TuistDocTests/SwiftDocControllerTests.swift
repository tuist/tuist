import Foundation
import TSCBasic
import TuistCoreTesting
import TuistDoc
import TuistDocTesting
import TuistSupport
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class SwiftDocControllerTests: TuistUnitTestCase {
    var subject: SwiftDocController!

    var binaryLocator: MockBinaryLocator!
    var moduleName: String!
    var baseURL: String!
    var outputDirectory: String!
    var sourcePaths: [AbsolutePath]!

    override func setUp() {
        binaryLocator = MockBinaryLocator()
        subject = SwiftDocController(binaryLocator: binaryLocator)

        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        binaryLocator = nil
        moduleName = nil
        baseURL = nil
        outputDirectory = nil
        sourcePaths = nil
    }

    func test_binary_not_found() {
        // Given
        moduleName = "Module"
        baseURL = "./"
        outputDirectory = "./tmp"
        sourcePaths = [AbsolutePath("/.")]

        binaryLocator.swiftDocPathStub = { throw BinaryLocatorError.swiftDocNotFound }

        // Then
        XCTAssertThrowsSpecific(
            // When
            try subject.generate(
                format: .html,
                moduleName: moduleName,
                baseURL: baseURL,
                outputDirectory: outputDirectory,
                sourcesPaths: sourcePaths
            ),
            BinaryLocatorError.swiftDocNotFound
        )
    }

    func test_parameters_swiftdoc_html() throws {
        // Given
        moduleName = "Module"
        baseURL = "/"
        outputDirectory = "/tmp"
        sourcePaths = [AbsolutePath("/.")]

        binaryLocator.swiftDocPathStub = { AbsolutePath("/path/to/swift-doc") }

        let arguments: [String] = [
            "/path/to/swift-doc",
            "generate",
            "--format",
            "html",
            "--module-name",
            moduleName,
            "--base-url",
            baseURL,
            "--output",
            outputDirectory,
            "/",
        ]
        system.succeedCommand(arguments, output: nil)

        // When
        try subject.generate(
            format: .html,
            moduleName: moduleName,
            baseURL: baseURL,
            outputDirectory: outputDirectory,
            sourcesPaths: sourcePaths
        )
    }

    func test_parameters_swiftdoc_commonmark() throws {
        // Given
        moduleName = "Module"
        baseURL = "./"
        outputDirectory = "./tmp"
        sourcePaths = [AbsolutePath("/.")]

        binaryLocator.swiftDocPathStub = { AbsolutePath("/path/to/swift-doc") }

        let arguments: [String] = [
            "/path/to/swift-doc",
            "generate",
            "--format",
            "commonmark",
            "--module-name",
            moduleName,
            "--base-url",
            baseURL,
            "--output",
            outputDirectory,
            "/",
        ]
        system.succeedCommand(arguments, output: nil)

        // When
        try subject.generate(
            format: .commonmark,
            moduleName: moduleName,
            baseURL: baseURL,
            outputDirectory: outputDirectory,
            sourcesPaths: sourcePaths
        )
    }
}
