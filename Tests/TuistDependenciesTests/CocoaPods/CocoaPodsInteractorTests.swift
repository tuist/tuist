import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CocoaPodsInteractorTests: TuistUnitTestCase {
    private var subject: CocoaPodsInteractor!

    override func setUp() {
        super.setUp()
        subject = CocoaPodsInteractor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_install_fetch() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(tuistDirectoryPath: stubbedPath, method: .fetch), CocoaPodsInteractorError.unimplemented)
    }

    func test_install_update() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(tuistDirectoryPath: stubbedPath, method: .update), CocoaPodsInteractorError.unimplemented)
    }
}
