import Foundation
import XCTest

@testable import ProjectDescription

final class DependencyCarthageRequirementTests: XCTestCase {
    func test_carthageRequirement_exact_codable() throws {
        let subject: Dependency.CarthageRequirement = .exact("1.0.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_upToNextMajor_codable() throws {
        let subject: Dependency.CarthageRequirement = .upToNextMajor("3.2.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_upToNextMinor_codable() throws {
        let subject: Dependency.CarthageRequirement = .upToNextMinor("5.3.1")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_branch_codable() throws {
        let subject: Dependency.CarthageRequirement = .branch("branch")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_revision_codable() throws {
        let subject: Dependency.CarthageRequirement = .revision("revision")
        XCTAssertCodable(subject)
    }
}
