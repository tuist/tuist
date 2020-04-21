import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class PrecompiledMetadataProviderTests: TuistUnitTestCase {
    var subject: PrecompiledMetadataProvider!

    override func setUp() {
        super.setUp()
        subject = PrecompiledMetadataProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_architectures() throws {
        // Given
        system.succeedCommand("/usr/bin/lipo", "-info", "/test.a", output: "Non-fat file: path is architecture: x86_64")

        // When
        let got = try subject.architectures(binaryPath: AbsolutePath("/test.a"))

        // Then
        XCTAssertEqual(got.first, .x8664)
    }

    func test_linking() throws {
        // Given
        system.succeedCommand("/usr/bin/file", "/test.a", output: "whatever dynamically linked")

        // When
        let got = try subject.linking(binaryPath: AbsolutePath("/test.a"))

        // Then
        XCTAssertEqual(got, .dynamic)
    }
}
