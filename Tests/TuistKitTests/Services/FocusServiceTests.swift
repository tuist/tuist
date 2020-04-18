import Foundation
import TSCBasic
import TuistCore
import TuistLoader
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class FocusServiceTests: TuistUnitTestCase {
    var subject: FocusService!
    var opener: MockOpener!
    var generator: MockProjectGenerator!

    override func setUp() {
        super.setUp()
        opener = MockOpener()
        generator = MockProjectGenerator()

        subject = FocusService(generator: generator,
                               opener: opener)
    }

    override func tearDown() {
        opener = nil
        generator = nil
        subject = nil
        super.tearDown()
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let error = NSError.test()
        generator.generateStub = { _, _ in
            throw error
        }
        XCTAssertThrowsError(try subject.run()) {
            XCTAssertEqual($0 as NSError?, error)
        }
    }

    func test_run() throws {
        let workspacePath = AbsolutePath("/test.xcworkspace")
        generator.generateStub = { _, _ in
            workspacePath
        }
        try subject.run()

        XCTAssertEqual(opener.openArgs.last?.0, workspacePath.pathString)
    }
}
