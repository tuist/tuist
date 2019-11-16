import Basic
import Foundation
import XCTest

@testable import TuistCore

final class PackageNodeTests: XCTestCase {
    func test_remotePackage_name() {
        // Given
        let path = AbsolutePath("/")
        let subject = PackageNode(package: .remote(url: "RemotePackage", requirement: .branch("master")), path: path)

        // When
        let got = subject.name

        // Then
        XCTAssertEqual(got, "RemotePackage")
    }

    func test_localPackage_name() {
        // Given
        let path = AbsolutePath("/")
        let subject = PackageNode(package: .local(path: AbsolutePath("/LocalPackage")), path: path)

        // When
        let got = subject.name

        // Then
        XCTAssertEqual(got, "/LocalPackage")
    }

    func test_remotePackage_isEqual_returnsTrue_when_thePathsAreTheSame() {
        // Given
        let path = AbsolutePath("/")
        let lhs = PackageNode(package: .remote(url: "url", requirement: .branch("master")), path: path)
        let rhs = PackageNode(package: .remote(url: "url", requirement: .branch("master")), path: path)

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func test_localPackage_isEqual_returnsTrue_when_thePathsAreTheSame() {
        // Given
        let path = AbsolutePath("/")
        let lhs = PackageNode(package: .local(path: AbsolutePath("/")), path: path)
        let rhs = PackageNode(package: .local(path: AbsolutePath("/")), path: path)

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func test_remotePackage_isEqual_returnsFalse_when_thePathsAreTheSame() {
        // Given
        let lhs = PackageNode(package: .remote(url: "url", requirement: .branch("master")), path: AbsolutePath("/"))
        let rhs = PackageNode(package: .remote(url: "url", requirement: .branch("master")), path: AbsolutePath("/other"))

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }

    func test_localPackage_isEqual_returnsFalse_when_thePathsAreTheSame() {
        // Given
        let lhs = PackageNode(package: .local(path: AbsolutePath("/")), path: AbsolutePath("/"))
        let rhs = PackageNode(package: .local(path: AbsolutePath("/")), path: AbsolutePath("/other"))

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }
}
