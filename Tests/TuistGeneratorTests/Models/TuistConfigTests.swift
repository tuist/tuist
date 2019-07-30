import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class TuistConfigTests: XCTestCase {
    func test_tuistConfig() {
        // When
        let tuistConfig = TuistConfig(generationOptions: [.xcodeProjectName("ThingOne")])
        let projectName = tuistConfig.generationOptions.first

        // Then
        XCTAssertEqual(tuistConfig.generationOptions.count, 1)
        if case let .xcodeProjectName(projectName)? = projectName {
            XCTAssertEqual(projectName, "ThingOne")
        }
    }
}
