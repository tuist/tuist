import Foundation
import Path
import XCTest
import TuistSupport
import FileSystem

@testable import TuistCore
@testable import TuistSupportTesting

final class XCFrameworkSignatureProviderIntegrationTests: TuistUnitTestCase {
    private var subject: XCFrameworkSignatureProvider!

    override func setUp() {
        super.setUp()
        subject = XCFrameworkSignatureProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_unsignedXCFramework_returnsUnsigned() async throws {
        // Given
        let path = fixturePath(path: try RelativePath(validating: "MyFramework.xcframework"))

        // When
        let result = try await subject.signature(of: path)

        // Then
        XCTAssertEqual(result, .unsigned)
    }

    func test_appleSignedXCFramework_returnsSignedByApple() async throws {
        // Given
        let path = fixturePath(path: try RelativePath(validating: "SignedXCFramework.xcframework"))

        // When
        let result = try await subject.signature(of: path)

        // Then
        XCTAssertEqual(result, .signedByApple(teamIdentifier: "U6LC622NKF", teamName: "Tuist GmbH"))
    }

    func test_selfSignedXCFramework_returnsSelfSignedFingerprint() async throws {
        // Given
        let path = fixturePath(path: try RelativePath(validating: "SelfSignedXCFramework.xcframework"))

        // When
        let result = try await subject.signature(of: path)

        // Then
        XCTAssertEqual(result, .selfSigned(fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"))
    }
}
