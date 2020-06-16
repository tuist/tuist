import RxBlocking
import RxSwift
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
        let observable = subject.observable(["echo", "hola"]).mapToString()

        // When
        let result = observable.toBlocking().materialize()

        // Then
        switch result {
        case let .completed(elements):
            XCTAssertEqual(elements.count, 1)
            XCTAssertTrue(elements.first?.value.spm_chomp() == "hola")
        case let .failed(elements, error):
            XCTAssertEqual(elements.count, 0)
            XCTFail("Expected command not to fail but failed with error: \(error)")
        }
    }

    func test_observable_when_it_errors() throws {
        // Given
        let observable = subject.observable(["/usr/bin/xcrun", "invalid"]).mapToString()

        // When
        let result = observable.toBlocking().materialize()

        // Then
        switch result {
        case .completed:
            XCTFail("expected command to fail but it did not")
        case let .failed(elements, error):
            XCTAssertTrue(elements.first(where: { $0.value.contains("errno=No such file or directory") }) != nil)
            XCTAssertTrue(error is TuistSupport.SystemError)
        }
    }

    func sandbox(_ name: String, value: String, do block: () throws -> Void) rethrows {
        try? ProcessEnv.setVar(name, value: value)
        _ = try? block()
        try? ProcessEnv.unsetVar(name)
    }
}
