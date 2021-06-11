import Foundation
import XCTest

@testable import ProjectDescription

final class DependenciesTests: XCTestCase {
    func test_dependencies_codable() throws {
        let subject = Dependencies(
            carthage: [
                .github(path: "Dependency1/Dependency1", requirement: .branch("BranchName")),
                .git(path: "Dependency2/Dependency2", requirement: .upToNext("1.2.3")),
            ],
            swiftPackageManager: [
                .local(path: "Path/Path"),
                .remote(url: "Dependency3/Dependency3", requirement: .exact("4.5.6")),
            ],
            platforms: [.iOS, .macOS, .tvOS, .watchOS]
        )
        XCTAssertCodable(subject)
    }
}
