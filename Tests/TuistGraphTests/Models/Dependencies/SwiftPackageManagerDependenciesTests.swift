import Foundation
import XCTest
@testable import TuistGraph
@testable import TuistSupportTesting

final class SwiftPackageManagerDependenciesTests: TuistUnitTestCase {
    func test_manifestValue_singleDependency() {
        // Given
        let subject = SwiftPackageManagerDependencies(
            [
                .remote(url: "url/url/url", requirement: .branch("branch")),
            ],
            productTypes: [:],
            baseSettings: .init(configurations: [:]),
            targetSettings: [:],
            projectOptions: [:]
        )

        // When
        let got = subject.manifestValue(isLegacy: false, packageManifestFolder: "/")

        // Then
        let expected = """
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: [
                .package(url: "url/url/url", branch: "branch"),
            ]
        )

        """
        XCTAssertEqual(got, expected)
    }

    func test_manifestValue_multipleDependencies() {
        // Given
        let subject = SwiftPackageManagerDependencies(
            [
                .remote(url: "xyz", requirement: .exact("10.10.10")),
                .remote(url: "foo/foo", requirement: .upToNextMinor("1.2.3")),
                .remote(url: "bar/bar", requirement: .upToNextMajor("3.2.1")),
                .remote(url: "http://xyz.com", requirement: .branch("develop")),
                .remote(url: "https://www.google.com/", requirement: .revision("a083aa1435eb35d8a1cb369115a7636cb4b65135")),
                .remote(url: "url/url/url", requirement: .range(from: "1.2.3", to: "5.2.1")),
                .local(path: "/path/path/path"),
            ],
            productTypes: [:],
            baseSettings: .init(configurations: [:]),
            targetSettings: [:],
            projectOptions: [:]
        )

        // When
        let got = subject.manifestValue(isLegacy: false, packageManifestFolder: "/path")

        // Then
        let expected = """
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: [
                .package(url: "xyz", exact: "10.10.10"),
                .package(url: "foo/foo", .upToNextMinor(from: "1.2.3")),
                .package(url: "bar/bar", from: "3.2.1"),
                .package(url: "http://xyz.com", branch: "develop"),
                .package(url: "https://www.google.com/", revision: "a083aa1435eb35d8a1cb369115a7636cb4b65135"),
                .package(url: "url/url/url", "1.2.3" ..< "5.2.1"),
                .package(path: "path/path"),
            ]
        )

        """
        XCTAssertEqual(got, expected)
    }

    func test_legacyManifestValue_singleDependency() {
        // Given
        let subject = SwiftPackageManagerDependencies(
            [
                .remote(url: "url/url/url", requirement: .branch("branch")),
            ],
            productTypes: [:],
            baseSettings: .init(configurations: [:]),
            targetSettings: [:],
            projectOptions: [:]
        )

        // When
        let got = subject.manifestValue(isLegacy: true, packageManifestFolder: "/path")

        // Then
        let expected = """
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: [
                .package(url: "url/url/url", .branch("branch")),
            ]
        )

        """
        XCTAssertEqual(got, expected)
    }

    func test_legacyManifestValue_multipleDependencies() {
        // Given
        let subject = SwiftPackageManagerDependencies(
            [
                .remote(url: "xyz", requirement: .exact("10.10.10")),
                .remote(url: "foo/foo", requirement: .upToNextMinor("1.2.3")),
                .remote(url: "bar/bar", requirement: .upToNextMajor("3.2.1")),
                .remote(url: "http://xyz.com", requirement: .branch("develop")),
                .remote(url: "https://www.google.com/", requirement: .revision("a083aa1435eb35d8a1cb369115a7636cb4b65135")),
                .remote(url: "url/url/url", requirement: .range(from: "1.2.3", to: "5.2.1")),
                .local(path: "/path/path/path"),
            ],
            productTypes: [:],
            baseSettings: .init(configurations: [:]),
            targetSettings: [:],
            projectOptions: [:]
        )

        // When
        let got = subject.manifestValue(isLegacy: true, packageManifestFolder: "/path")

        // Then
        let expected = """
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: [
                .package(url: "xyz", .exact("10.10.10")),
                .package(url: "foo/foo", .upToNextMinor(from: "1.2.3")),
                .package(url: "bar/bar", .upToNextMajor(from: "3.2.1")),
                .package(url: "http://xyz.com", .branch("develop")),
                .package(url: "https://www.google.com/", .revision("a083aa1435eb35d8a1cb369115a7636cb4b65135")),
                .package(url: "url/url/url", "1.2.3" ..< "5.2.1"),
                .package(path: "path/path"),
            ]
        )

        """
        XCTAssertEqual(got, expected)
    }
}
