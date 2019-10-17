import Basic
import Foundation
import XCTest

@testable import TuistGenerator

final class PackageNodeTests: XCTestCase {
    func test_remotePackage_name() {
        // Given
        let path = AbsolutePath("/")
        let subject = PackageNode(packageType: .remote(url: "url", productName: "RemotePackage", versionRequirement: .branch("master")), path: path)

        // When
        let got = subject.name

        // Then
        XCTAssertEqual(got, "RemotePackage")
    }

    func test_localPackage_name() {
        // Given
        let path = AbsolutePath("/")
        let subject = PackageNode(packageType: .local(path: RelativePath(""), productName: "LocalPackage"), path: path)

        // When
        let got = subject.name

        // Then
        XCTAssertEqual(got, "LocalPackage")
    }

    func test_remotePackage_isEqual_returnsTrue_when_thePathsAreTheSame() {
        // Given
        let path = AbsolutePath("/")
        let lhs = PackageNode(packageType: .remote(url: "url", productName: "RemotePackage", versionRequirement: .branch("master")), path: path)
        let rhs = PackageNode(packageType: .remote(url: "url", productName: "RemotePackage", versionRequirement: .branch("master")), path: path)

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func test_localPackage_isEqual_returnsTrue_when_thePathsAreTheSame() {
        // Given
        let path = AbsolutePath("/")
        let lhs = PackageNode(packageType: .local(path: RelativePath(""), productName: "LocalPackage"), path: path)
        let rhs = PackageNode(packageType: .local(path: RelativePath(""), productName: "LocalPackage"), path: path)

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func test_remotePackage_isEqual_returnsFalse_when_thePathsAreTheSame() {
        // Given
        let lhs = PackageNode(packageType: .remote(url: "url", productName: "RemotePackage", versionRequirement: .branch("master")), path: AbsolutePath("/"))
        let rhs = PackageNode(packageType: .remote(url: "url", productName: "RemotePackage", versionRequirement: .branch("master")), path: AbsolutePath("/other"))

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }

    func test_localPackage_isEqual_returnsFalse_when_thePathsAreTheSame() {
        // Given
        let lhs = PackageNode(packageType: .local(path: RelativePath(""), productName: "LocalPackage"), path: AbsolutePath("/"))
        let rhs = PackageNode(packageType: .local(path: RelativePath(""), productName: "LocalPackage"), path: AbsolutePath("/other"))

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }
}
