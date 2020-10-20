import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class TargetScriptsContentHasherTests: TuistUnitTestCase {
    private var subject: TargetScriptsContentHasher!
    private var mockContentHasher: MockContentHashing!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHashing()
        subject = TargetScriptsContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash() throws {
        // Given
        let first = TargetScript(name: "First Test",
                                 script: "echo 'first'",
                                 showEnvVarsInLog: true)
        let second = TargetScript(name: "Second test",
                                  script: "echo 'second'",
                                  showEnvVarsInLog: false)

        // When
        _ = try subject.hash(targetScripts: [first, second])

        // Then
        let expected = [
            first.name, first.script, "\(first.showEnvVarsInLog)",
            second.name, second.script, "\(second.showEnvVarsInLog)",
        ]
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }
}
