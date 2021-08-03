import Foundation
import XCTest
@testable import ProjectDescription

final class ProjectOptionTests: XCTestCase {
    func test_toJSON() {
        let subject = ProjectOption.textSettings(
            usesTabs: true,
            indentWidth: 0,
            tabWidth: 0,
            wrapsLines: true
        )
        XCTAssertCodable(subject)
    }
}
