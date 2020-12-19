import Foundation
import XCTest

@testable import ProjectDescription

final class DependencyTests: XCTestCase {
    func test_dependency_carthage_codable() throws {
        let subject: Dependency = .carthage(name: "Name", requirement: .revision("xyz"), platforms: [.iOS, .macOS, .tvOS, .watchOS])
        XCTAssertCodable(subject)
    }
}
