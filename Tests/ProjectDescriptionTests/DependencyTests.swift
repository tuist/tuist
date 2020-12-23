import Foundation
import XCTest

@testable import ProjectDescription

final class DependencyTests: XCTestCase {
    func test_dependency_carthage_codable() throws {
        let subject: Dependency = .carthage(origin: .github(path: "Dependency/Dependency"), requirement: .revision("xyz"), platforms: [.iOS, .macOS, .tvOS, .watchOS])
        XCTAssertCodable(subject)
    }
    
    // MARK: - Carthage Origin tests
    
    func test_carthageOrigin_github_codable() throws {
        let subject: Dependency.CarthageOrigin = .github(path: "Path/Path")
        XCTAssertCodable(subject)
    }
    
    func test_carthageOrigin_git_codable() throws {
        let subject: Dependency.CarthageOrigin = .git(path: "Git/Git")
        XCTAssertCodable(subject)
    }
    
    func test_carthageOrigin_binary_codable() throws {
        let subject: Dependency.CarthageOrigin = .binary(path: "file:///some/Path/MyFramework.json")
        XCTAssertCodable(subject)
    }
    
    // MARK: - Carthage Requirement tests
    
    func test_carthageRequirement_exact_codable() throws {
        let subject: Dependency.CarthageRequirement = .exact("1.0.0")
        XCTAssertCodable(subject)
    }

    func test_carthageRequirement_upToNext_codable() throws {
        let subject: Dependency.CarthageRequirement = .upToNext("3.2.0")
        XCTAssertCodable(subject)
    }
    
    func test_carthageRequirement_atLeast_codable() throws {
        let subject: Dependency.CarthageRequirement = .atLeast("3.2.0")
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
