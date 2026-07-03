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
                .init(
                    path: "Generated/File.xcfilelist",
                    generatedPlaceholderPath: try AbsolutePath(validating: "/Generated/File.xcfilelist")
                ),
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_decoding_whenFileListPathsAreStrings() throws {
        // Given
        let data = try JSONSerialization.data(withJSONObject: [
            "name": "name",
            "script": ["embedded": ["_0": script]],
            "order": "pre",
            "inputPaths": [],
            "inputFileListPaths": ["Inputs.xcfilelist"],
            "outputPaths": [],
            "outputFileListPaths": ["Outputs.xcfilelist"],
            "showEnvVarsInLog": true,
            "runForInstallBuildsOnly": false,
            "shellPath": "/bin/sh",
        ])

        // When
        let got = try JSONDecoder().decode(TargetScript.self, from: data)

        // Then
        XCTAssertEqual(got.inputFileListPaths, ["Inputs.xcfilelist"])
        XCTAssertEqual(got.outputFileListPaths, ["Outputs.xcfilelist"])
    }
}
