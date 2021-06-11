import Foundation
import XCTest

@testable import ProjectDescription

final class SwiftPackageManagerDependenciesTests: XCTestCase {
    func test_swiftPackageManagerDependencies_codable() {
        let subject: SwiftPackageManagerDependencies = [
            .local(path: "Path/Path"),
            .remote(url: "Dependency3/Dependency3", requirement: .exact("4.5.6")),
        ]
        XCTAssertCodable(subject)
    }
}
