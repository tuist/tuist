import FileSystem
import Foundation
import Path
import Testing
import TuistSupport

@testable import TuistCore
@testable import TuistTesting

struct XCFrameworkSignatureProviderTests {
    private var subject: XCFrameworkSignatureProvider!

    init() {
        subject = XCFrameworkSignatureProvider()
    }

    @Test func unsignedXCFramework_returnsUnsigned() async throws {
        // Given
        let path = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "MyFramework.xcframework"))

        // When
        let result = try await subject.signature(of: path)

        // Then
        #expect(result == .unsigned)
    }

    @Test func appleSignedXCFramework_returnsSignedWithAppleCertificate() async throws {
        // Given
        let path = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "SignedXCFramework.xcframework"))

        // When
        let result = try await subject.signature(of: path)

        // Then
        #expect(result == .signedWithAppleCertificate(teamIdentifier: "U6LC622NKF", teamName: "Tuist GmbH"))
    }

    @Test func selfSignedXCFramework_returnsSelfSignedFingerprint() async throws {
        // Given
        let path = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "SelfSignedXCFramework.xcframework"))

        // When
        let result = try await subject.signature(of: path)

        // Then
        #expect(result == .selfSigned(fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"))
    }
}
