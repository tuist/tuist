import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistDoc
@testable import TuistSupportTesting

final class TuistDocIntegrationTests: TuistTestCase {
    var subject: SwiftDocController!

    override func setUp() {
        super.setUp()
        subject = SwiftDocController()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_generate_markdown_documentation() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        let content = """
        /// SwiftDoc controller protocol passed in initializers for dependency injection
        public protocol SwiftDocControlling {
        /// Generates the documentation for a given module
        /// - Parameters:
        ///   - format: Format of the output
        ///   - moduleName: Name of the target.
        ///   - baseURL: Base URL for all the documentation relative paths
        ///   - outputDirectory: Directory where the documentation will be placed
        ///   - sourcesPaths: Paths to the files to be documented
        func generate(format: SwiftDocFormat,
                    moduleName: String,
                    baseURL: String,
                    outputDirectory: String,
                    sourcesPaths paths: [AbsolutePath]) throws
        }
        """

        let sourcePath = temporaryPath.appending(component: "SwiftDocControlling.swift")
        try content.write(to: sourcePath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        try subject.generate(format: .commonmark,
                             moduleName: "TuistDoc",
                             baseURL: "/.",
                             outputDirectory: temporaryPath.pathString,
                             sourcesPaths: [sourcePath])
    }

    func test_generate_html_documentation() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        let content = """
        /// SwiftDoc controller protocol passed in initializers for dependency injection
        public protocol SwiftDocControlling {
        /// Generates the documentation for a given module
        /// - Parameters:
        ///   - format: Format of the output
        ///   - moduleName: Name of the target.
        ///   - baseURL: Base URL for all the documentation relative paths
        ///   - outputDirectory: Directory where the documentation will be placed
        ///   - sourcesPaths: Paths to the files to be documented
        func generate(format: SwiftDocFormat,
                    moduleName: String,
                    baseURL: String,
                    outputDirectory: String,
                    sourcesPaths paths: [AbsolutePath]) throws
        }
        """

        let sourcePath = temporaryPath.appending(component: "SwiftDocControlling.swift")
        try content.write(to: sourcePath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        try subject.generate(format: .html,
                             moduleName: "TuistDoc",
                             baseURL: "/.",
                             outputDirectory: temporaryPath.pathString,
                             sourcesPaths: [sourcePath])
    }
}
