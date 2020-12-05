import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistSupportTesting

final class OtoolControllerIntegrationTests: TuistTestCase {
    var subject: OtoolController!

    override func setUp() {
        super.setUp()
        subject = OtoolController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    /// If this test fails, the contract that we've implemented  for otool is broken
    func test_loading_AlamofireImage_loads_Alamofire() throws {
        // Given
        let carthagePath = try temporaryFixture("Carthage/")
        let frameworkPath = FileHandler.shared.glob(carthagePath, glob: "**/AlamofireImage.framework").first!
        let alamofirePath = FileHandler.shared.glob(carthagePath, glob: "**/Alamofire.framework").first!
        let alamofireBinary = alamofirePath.appending(RelativePath("Alamofire"))

        // When
        let binaryPath = frameworkPath.appending(RelativePath("AlamofireImage"))
        let dependencies = try subject.dylibDependenciesBinaryPath(forBinaryAt: binaryPath)
            .toBlocking()
            .first()!

        // Then
        XCTAssertTrue(alamofireBinary == dependencies.first!)
    }

}
