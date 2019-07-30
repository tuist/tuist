import Foundation
import XCTest
@testable import ProjectDescription

final class TuistConfigTests: XCTestCase {
    func test_tuistconfig_toJSON() throws {
        let tuistConfig = TuistConfig(generationOptions:
            [.generateManifest,
             .xcodeProjectName("someprefix-\(.projectName)")])

        let encoded = try JSONEncoder().encode(tuistConfig)
        let decoded = try JSONDecoder().decode(TuistConfig.self, from: encoded)

        XCTAssertEqual(tuistConfig, decoded)
    }
}
