import Foundation
import Path
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class FrameworkMetadataProviderIntegrationTests: TuistTestCase {
    var subject: FrameworkMetadataProvider!

    override func setUp() {
        super.setUp()
        subject = FrameworkMetadataProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_bcsymbolmapPaths() async throws {
        // Given
        let testPath = try await temporaryFixture("PrebuiltFramework/")
        let frameworkPath = FileHandler.shared.glob(testPath, glob: "*.framework").first!

        // When
        let got = try await subject.bcsymbolmapPaths(frameworkPath: frameworkPath).sorted()

        // Then
        XCTAssertEqual(got, [
            testPath.appending(component: "2510FE01-4D40-3956-BB71-857D3B2D9E73.bcsymbolmap"),
            testPath.appending(component: "773847A9-0D05-35AF-9865-94A9A670080B.bcsymbolmap"),
        ])
    }

    func test_dsymPath() async throws {
        // Given
        let testPath = try await temporaryFixture("PrebuiltFramework/")
        let frameworkPath = FileHandler.shared.glob(testPath, glob: "*.framework").first!

        // When
        let got = try await subject.dsymPath(frameworkPath: frameworkPath)

        // Then
        XCTAssertEqual(got, testPath.appending(component: "\(frameworkPath.basename).dSYM"))
    }
}
