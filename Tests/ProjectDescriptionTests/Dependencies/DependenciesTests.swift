import Foundation
import XCTest

@testable import ProjectDescription

final class DependenciesTests: XCTestCase {
    func test_dependencies_codable() throws {
        let subject = Dependencies(
            carthageDependencies: .init(
                dependencies: [
                    .github(path: "Dependency1/Dependency1", requirement: .branch("BranchName")),
                    .git(path: "Dependency2/Dependency2", requirement: .upToNext("1.2.3")),
                ],
                options: .init(
                    platforms: [.iOS, .macOS],
                    useXCFrameworks: true
                )
            )
        )
        XCTAssertCodable(subject)
    }
}
