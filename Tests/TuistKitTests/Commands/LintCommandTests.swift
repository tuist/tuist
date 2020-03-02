import Basic
import Foundation
import SPMUtility
import XCTest

@testable import TuistCoreTesting
@testable import TuistGeneratorTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class LintCommandTests: TuistUnitTestCase {
    var parser: ArgumentParser!
    var graphLinter: MockGraphLinter!
    var environmentLinter: MockEnvironmentLinter!
    var manifestLoader: MockManifestLoader!
    var graphLoader: MockGraphLoader!
    var subject: LintCommand!

    override func setUp() {
        parser = ArgumentParser.test()
        graphLinter = MockGraphLinter()
        environmentLinter = MockEnvironmentLinter()
        manifestLoader = MockManifestLoader()
        graphLoader = MockGraphLoader()
        subject = LintCommand(graphLinter: graphLinter,
                              environmentLinter: environmentLinter,
                              manifestLoading: manifestLoader,
                              graphLoader: graphLoader,
                              parser: parser)
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        graphLinter = nil
        environmentLinter = nil
        manifestLoader = nil
        graphLoader = nil
        subject = nil
    }

    func test_command() {
        XCTAssertEqual(LintCommand.command, "lint")
    }

    func test_overview() {
        XCTAssertEqual(LintCommand.overview, "Lints a workspace or a project that check whether they are well configured.")
    }
}
