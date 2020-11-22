import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CocoapodsInteractorTests: TuistUnitTestCase {
    private var subject: CocoapodsInteractor!

    override func setUp() {
        super.setUp()
        subject = CocoapodsInteractor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_install_fetch() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(at: stubbedPath, method: .fetch), CocoapodsInteractorError.unimplemented)
    }

    func test_install_update() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(at: stubbedPath, method: .update), CocoapodsInteractorError.unimplemented)
    }
}
