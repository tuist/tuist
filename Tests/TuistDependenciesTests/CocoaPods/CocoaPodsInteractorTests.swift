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

    func test_fetch() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.fetch(dependenciesDirectory: stubbedPath), CocoaPodsInteractorError.unimplemented)
    }
}
