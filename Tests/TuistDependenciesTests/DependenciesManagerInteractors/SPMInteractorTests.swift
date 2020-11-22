import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class SPMInteractorTests: TuistUnitTestCase {
    private var subject: SPMInteractor!

    override func setUp() {
        super.setUp()
        subject = SPMInteractor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_install_fetch() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(at: stubbedPath, method: .fetch), SPMInteractorError.unimplemented)
    }

    func test_install_update() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(at: stubbedPath, method: .update), SPMInteractorError.unimplemented)
    }
}
