import Basic
import Foundation
import SPMUtility
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CacheCommandTests: TuistUnitTestCase {
    var subject: CacheCommand!
    var parser: ArgumentParser!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        subject = CacheCommand(parser: parser)
    }

    override func tearDown() {
        parser = nil
        subject = nil
        super.tearDown()
    }

    func test_name() {
        XCTAssertEqual(CacheCommand.command, "cache")
    }

    func test_overview() {
        XCTAssertEqual(CacheCommand.overview, "Cache frameworks as .xcframeworks to speed up build times in generated projects")
    }
}
