import Foundation
import XCTest

@testable import ProjectDescription

final class DependenciesTests: XCTestCase {
    func test_dependencies_codable() throws {
        let subject = Dependencies([
            .carthage(name: "Dependency1", requirement: .branch("BranchName"), platforms: [.iOS]),
            .carthage(name: "Dependency2", requirement: .upToNextMajor("1.2.3"), platforms: [.tvOS, .macOS]),
        ])
        XCTAssertCodable(subject)
    }
}
