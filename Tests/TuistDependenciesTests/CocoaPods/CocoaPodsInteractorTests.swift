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

    func test_install_unimplemented() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(dependenciesDirectory: stubbedPath, shouldUpdate: false), CocoaPodsInteractorError.unimplemented)
    }

    func test_clean_unimplemented() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.clean(dependenciesDirectory: stubbedPath), CocoaPodsInteractorError.unimplemented)
    }
}
