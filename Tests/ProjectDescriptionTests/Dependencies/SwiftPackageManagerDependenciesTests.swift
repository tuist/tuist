import Foundation
import XCTest

@testable import ProjectDescription

final class SwiftPackageManagerDependenciesTests: XCTestCase {
    func test_swiftPackageManagerDependencies_codable() {
        let subject: SwiftPackageManagerDependencies = []
        XCTAssertCodable(subject)
    }
}
