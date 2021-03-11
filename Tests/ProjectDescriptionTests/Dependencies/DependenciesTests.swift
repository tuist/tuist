import Foundation
import XCTest

@testable import ProjectDescription

final class DependenciesTests: XCTestCase {
    func test_dependencies_codable() throws {
        let subject = Dependencies(
            carthage: .carthage(
                [
                    .github(path: "Dependency1/Dependency1", requirement: .branch("BranchName")),
                    .git(path: "Dependency2/Dependency2", requirement: .upToNext("1.2.3")),
                ],
                platforms: [.iOS, .macOS],
                options: [.useXCFrameworks, .noUseBinaries]
            ),
            swiftPackageManager: .swiftPackageManager(
                [
                    .local(path: "Path/Path"),
                    .remote(url: "Dependency3/Dependency3", requirement: .exact("4.5.6")),
                ]
            )
        )
        XCTAssertCodable(subject)
    }
}
