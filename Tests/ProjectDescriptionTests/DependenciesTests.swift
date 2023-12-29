import Foundation
import XCTest

@testable import ProjectDescription

final class DependenciesTests: XCTestCase {
    func test_Dependencies_codable() {
        let subject: Dependencies = .init()
        XCTAssertCodable(subject)
    }
}
