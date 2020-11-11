import Foundation
import TSCBasic
import TuistCore
import TuistLoader
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class UpServiceTests: TuistUnitTestCase {
    var subject: UpService!
    var setupLoader: MockSetupLoader!

    override func setUp() {
        super.setUp()
        setupLoader = MockSetupLoader()
        subject = UpService(setupLoader: setupLoader)
    }

    override func tearDown() {
        subject = nil
        setupLoader = nil
        super.tearDown()
    }

    func test_run_configures_the_environment() throws {
        // given
        let temporaryPath = try self.temporaryPath()
        var receivedPaths = [String]()
        setupLoader.meetStub = { path, _ in
            receivedPaths.append(path.pathString)
        }

        // when
        try subject.run(path: temporaryPath.pathString)

        // then
        XCTAssertEqual(receivedPaths, [temporaryPath.pathString])
        XCTAssertEqual(setupLoader.meetCount, 1)
    }

    func test_run_uses_the_given_path() throws {
        // given
        let path = AbsolutePath("/path")
        var receivedPaths = [String]()
        setupLoader.meetStub = { path, _ in
            receivedPaths.append(path.pathString)
        }

        // when
        try subject.run(path: path.pathString)

        // then
        XCTAssertEqual(receivedPaths, ["/path"])
        XCTAssertEqual(setupLoader.meetCount, 1)
    }
}
