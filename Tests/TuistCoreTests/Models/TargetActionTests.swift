import Foundation
import TSCBasic
import XCTest
@testable import TuistCore

private let script = """
echo 'Hello World'
wd=$(pwd)
echo "$wd"
"""

final class TargetActionTests: XCTestCase {
    func test_embedded_script() throws {
        let subject = TargetAction(name: "name", order: .pre, script: script)

        let shellScript = try subject.shellScript(sourceRootPath: .root)
        XCTAssertEqual(script, shellScript)
        XCTAssertNotNil(subject.embeddedScript)
    }
}
