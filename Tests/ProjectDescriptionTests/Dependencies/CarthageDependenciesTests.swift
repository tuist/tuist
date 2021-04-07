import Foundation
import XCTest

@testable import ProjectDescription

final class CarthageDependenciesTests: XCTestCase {
    func test_carthageDependencies_codable() throws {
        let subject: CarthageDependencies = .carthage(
            [
                .github(path: "Dependency/Dependency", requirement: .revision("xyz")),
                .git(path: "Git/Git", requirement: .atLeast("1.2.3")),
            ],
            options: [.useXCFrameworks, .noUseBinaries]
        )
        XCTAssertCodable(subject)
    }

    // MARK: - Carthage Origin tests

    func test_carthageDependency_github_codable() throws {
        let subject: CarthageDependencies.Dependency = .github(path: "Path/Path", requirement: .branch("branch_name"))
        XCTAssertCodable(subject)
    }

    func test_carthageDependency_git_codable() throws {
        let subject: CarthageDependencies.Dependency = .git(path: "Git/Git", requirement: .exact("1.5.123"))
        XCTAssertCodable(subject)
    }

    func test_carthageDependency_binary_codable() throws {
        let subject: CarthageDependencies.Dependency = .binary(path: "file:///some/Path/MyFramework.json", requirement: .upToNext("5.6.9"))
        XCTAssertCodable(subject)
    }

    // MARK: - Carthage Requirement tests

    func test_carthageRequirement_exact_codable() throws {
        let subject: CarthageDependencies.Requirement = .exact("1.0.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_upToNext_codable() throws {
        let subject: CarthageDependencies.Requirement = .upToNext("3.2.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_atLeast_codable() throws {
        let subject: CarthageDependencies.Requirement = .atLeast("3.2.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_branch_codable() throws {
        let subject: CarthageDependencies.Requirement = .branch("branch")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_revision_codable() throws {
        let subject: CarthageDependencies.Requirement = .revision("revision")
        XCTAssertCodable(subject)
    }

    // MARK: - Carthage Options tests

    func test_carthageOptions_useXCFrameworks_codable() throws {
        let subject: CarthageDependencies.Options = .useXCFrameworks
        XCTAssertCodable(subject)
    }

    func test_carthageOptions_noUseBinaries_codable() throws {
        let subject: CarthageDependencies.Options = .noUseBinaries
        XCTAssertCodable(subject)
    }
}
