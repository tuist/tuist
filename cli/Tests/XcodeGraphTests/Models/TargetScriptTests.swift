import Foundation
import Path
import XCTest
@testable import XcodeGraph

private let script = """
echo 'Hello World'
wd=$(pwd)
echo "$wd"
"""

final class TargetScriptTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = TargetScript(
            name: "name",
            order: .pre,
            script: .embedded(script),
            inputFileListPaths: [
                .generated(try AbsolutePath(validating: "/Generated/File.xcfilelist")),
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
