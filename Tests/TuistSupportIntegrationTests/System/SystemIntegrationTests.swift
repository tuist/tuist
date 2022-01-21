import TSCBasic
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class SystemIntegrationTests: TuistTestCase {
    var subject: System!

    override func setUp() {
        super.setUp()
        subject = System()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_run_valid_command() {
        XCTAssertNoThrow(try subject.run(["ls"]))
    }

    func test_run_invalid_command() {
        XCTAssertThrowsError(try subject.run(["abcdef", "ghi"]))
    }

    func test_run_valid_command_that_returns_nonzero_exit() {
        XCTAssertThrowsError(try subject.run(["ls", "abcdefghi"]))
    }

    func test_observable() throws {
        // Given
        let publisher = subject.publisher(["echo", "hola"]).mapToString()

        // When
        let elements = try publisher.toBlocking()

        // Then
        XCTAssertEqual(elements.count, 1)
        XCTAssertTrue(elements.first?.value.spm_chomp() == "hola")
    }

    func test_observable_when_it_errors() throws {
        // Given
        let publisher = subject.publisher(["/usr/bin/xcrun", "invalid"]).mapToString()

        do {
            // When
            _ = try publisher.toBlocking()
            XCTFail("expected command to fail but it did not")
        } catch {
            // Then
            XCTAssertTrue(error is TuistSupport.SystemError)
        }
    }

    func sandbox(_ name: String, value: String, do block: () throws -> Void) rethrows {
        try? ProcessEnv.setVar(name, value: value)
        _ = try? block()
        try? ProcessEnv.unsetVar(name)
    }
}
