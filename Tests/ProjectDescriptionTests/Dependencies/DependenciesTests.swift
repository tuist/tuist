import Foundation
import XCTest

@testable import ProjectDescription

final class DependenciesTests: XCTestCase {
    func test_dependencies_codable() throws {
        let subject = Dependencies(
            swiftPackageManager: .init(),
            platforms: [.iOS, .macOS, .tvOS, .watchOS]
        )
        XCTAssertCodable(subject)
    }
}
