import ProjectDescription
import TuistSupportTesting
import XCTest

class PackageTests: XCTestCase {
    func test_package_remotePackages_codable() throws {
        // Given
        let subject = Package.package(
            url: "https://github.com/Swinject/Swinject",
            .upToNextMajor(from: "2.6.2")
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_package_localPackages_codable() throws {
        // Given
        let subject = Package.package(path: "foo/bar")

        // Then
        XCTAssertCodable(subject)
    }
}
