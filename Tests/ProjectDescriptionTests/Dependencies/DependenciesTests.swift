import Foundation
import XCTest

@testable import ProjectDescription

final class DependenciesTests: XCTestCase {
    func test_dependencies_codable() throws {
        let subject = Dependencies([
            .carthage(origin: .github(path: "Dependency1/Dependency1"), requirement: .branch("BranchName"), platforms: [.iOS]),
            .carthage(origin: .git(path: "Dependency2/Dependency2"), requirement: .upToNext("1.2.3"), platforms: [.tvOS, .macOS]),
        ])
        XCTAssertCodable(subject)
    }
}
