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

    func test_run_output_is_redirected() throws {
        var output = ""
        try subject.run(
            ["echo", "hola"],
            verbose: false,
            environment: System.shared.env,
            redirection: .stream(stdout: { bytes in
                output = String(decoding: bytes, as: Unicode.UTF8.self)
            }, stderr: { _ in })
        )

        XCTAssertEqual(output.spm_chomp(), "hola")
    }

    func test_run_errors() throws {
        do {
            try subject.runAndPrint(["/usr/bin/xcrun", "invalid"], verbose: false, environment: System.shared.env)
            XCTFail("expected command to fail but it did not")
        } catch {
            XCTAssertTrue(error is TuistSupport.SystemError)
        }
    }

    func sandbox(_ name: String, value: String, do block: () throws -> Void) rethrows {
        try? ProcessEnv.setVar(name, value: value)
        _ = try? block()
        try? ProcessEnv.unsetVar(name)
    }
}
