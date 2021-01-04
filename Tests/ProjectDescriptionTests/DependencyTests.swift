import Foundation
import XCTest

@testable import ProjectDescription

final class DependencyTests: XCTestCase {
    func test_dependency_carthage_codable() {
        let subject: Dependency = .carthage(origin: .github(path: "Dependency/Dependency"), requirement: .revision("xyz"), platforms: [.iOS, .macOS, .tvOS, .watchOS])
        XCTAssertCodable(subject)
    }

    func test_dependency_spm_codable() {
        let subject: Dependency = .spm(url: "Path/Path", requirement: .exact("1.2.3"))
        XCTAssertCodable(subject)
    }

    // MARK: - Carthage Origin tests

    func test_carthageOrigin_github_codable() {
        let subject: Dependency.CarthageOrigin = .github(path: "Path/Path")
        XCTAssertCodable(subject)
    }

    func test_carthageOrigin_git_codable() {
        let subject: Dependency.CarthageOrigin = .git(path: "Git/Git")
        XCTAssertCodable(subject)
    }

    func test_carthageOrigin_binary_codable() {
        let subject: Dependency.CarthageOrigin = .binary(path: "file:///some/Path/MyFramework.json")
        XCTAssertCodable(subject)
    }

    // MARK: - Carthage Requirement tests

    func test_carthageRequirement_exact_codable() {
        let subject: Dependency.CarthageRequirement = .exact("1.0.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_upToNext_codable() {
        let subject: Dependency.CarthageRequirement = .upToNext("3.2.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_atLeast_codable() {
        let subject: Dependency.CarthageRequirement = .atLeast("3.2.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_branch_codable() {
        let subject: Dependency.CarthageRequirement = .branch("branch")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_revision_codable() {
        let subject: Dependency.CarthageRequirement = .revision("revision")
        XCTAssertCodable(subject)
    }

    // MARK: - SPM Requirement tests

    func test_spmRequirement_exact_codable() {
        let subject: Dependency.SPMRequirement = .exact("1.2.3")
        XCTAssertCodable(subject)
    }

    func test_spmRequirement_upToNextMajor_codable() {
        let subject: Dependency.SPMRequirement = .upToNextMajor("2.2.1")
        XCTAssertCodable(subject)
    }

    func test_spmRequirement_upToNextMinor_codable() {
        let subject: Dependency.SPMRequirement = .upToNextMinor("4.4.1")
        XCTAssertCodable(subject)
    }

    func test_spmRequirement_atLeast_codable() {
        let subject: Dependency.SPMRequirement = .atLeast("9.0.1")
        XCTAssertCodable(subject)
    }

    func test_spmRequirement_range_codable() {
        let subject: Dependency.SPMRequirement = .range("9.0.1" ..< "10.1.0")
        XCTAssertCodable(subject)
    }

    func test_spmRequirement_closedRange_codable() {
        let subject: Dependency.SPMRequirement = .closedRange("1.2.1" ... "7.1.4")
        XCTAssertCodable(subject)
    }

    func test_spmRequirement_branch_codable() {
        let subject: Dependency.SPMRequirement = .branch("branch")
        XCTAssertCodable(subject)
    }

    func test_spmRequirement_revision_codable() {
        let subject: Dependency.SPMRequirement = .revision("revision")
        XCTAssertCodable(subject)
    }
}
