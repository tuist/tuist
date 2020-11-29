import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class SwiftPackageManagerInteractorTests: TuistUnitTestCase {
    private var subject: SwiftPackageManagerInteractor!

    override func setUp() {
        super.setUp()
        subject = SwiftPackageManagerInteractor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_install_fetch() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(tuistDirectoryPath: stubbedPath, method: .fetch), SwiftPackageManagerInteractorError.unimplemented)
    }

    func test_install_update() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertThrowsSpecific(try subject.install(tuistDirectoryPath: stubbedPath, method: .update), SwiftPackageManagerInteractorError.unimplemented)
    }
}
