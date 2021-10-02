import Foundation
import TSCBasic
import XCTest
@testable import TuistGraph

private let script = """
echo 'Hello World'
wd=$(pwd)
echo "$wd"
"""

final class TargetScriptTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = TargetScript(name: "name", order: .pre, script: .embedded(script))

        // Then
        XCTAssertCodable(subject)
    }

    func test_embedded_script() throws {
        let subject = TargetScript(name: "name", order: .pre, script: .embedded(script))

        let shellScript = try subject.shellScript(sourceRootPath: .root)
        XCTAssertEqual(script, shellScript)
        XCTAssertNotNil(subject.embeddedScript)
    }
}
