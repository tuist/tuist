import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class PrintableStringTests: TuistUnitTestCase {
    func test_raw_description_when_colored_output() {
        environment.shouldOutputBeColoured = true
        let value = PrintableString.Token.raw("test")
        XCTAssertEqual(value.description, "test")
    }

    func test_raw_description_when_not_colored_output() {
        environment.shouldOutputBeColoured = false
        let value = PrintableString.Token.raw("test")
        XCTAssertEqual(value.description, "test")
    }

    func test_command_description_when_colored_output() {
        environment.shouldOutputBeColoured = true
        let value = PrintableString.Token.command("test")
        XCTAssertEqual(value.description, "test".cyan())
    }

    func test_command_description_when_not_colored_output() {
        environment.shouldOutputBeColoured = false
        let value = PrintableString.Token.command("test")
        XCTAssertEqual(value.description, "test")
    }

    func test_keystroke_description_when_colored_output() {
        environment.shouldOutputBeColoured = true
        let value = PrintableString.Token.keystroke("test")
        XCTAssertEqual(value.description, "test".cyan())
    }

    func test_keystroke_description_when_not_colored_output() {
        environment.shouldOutputBeColoured = false
        let value = PrintableString.Token.keystroke("test")
        XCTAssertEqual(value.description, "test")
    }

    func test_bold_description_when_colored_output() {
        environment.shouldOutputBeColoured = true
        let value = PrintableString.Token.bold("test")
        XCTAssertEqual(value.description, "test".bold())
    }

    func test_bold_description_when_not_colored_output() {
        environment.shouldOutputBeColoured = false
        let value = PrintableString.Token.bold("test")
        XCTAssertEqual(value.description, "test")
    }

    func test_error_description_when_colored_output() {
        environment.shouldOutputBeColoured = true
        let value = PrintableString.Token.error("test")
        XCTAssertEqual(value.description, "test".red())
    }

    func test_error_description_when_not_colored_output() {
        environment.shouldOutputBeColoured = false
        let value = PrintableString.Token.error("test")
        XCTAssertEqual(value.description, "test")
    }

    func test_success_description_when_colored_output() {
        environment.shouldOutputBeColoured = true
        let value = PrintableString.Token.success("test")
        XCTAssertEqual(value.description, "test".green())
    }

    func test_success_description_when_not_colored_output() {
        environment.shouldOutputBeColoured = false
        let value = PrintableString.Token.success("test")
        XCTAssertEqual(value.description, "test")
    }

    func test_warning_description_when_colored_output() {
        environment.shouldOutputBeColoured = true
        let value = PrintableString.Token.warning("test")
        XCTAssertEqual(value.description, "test".yellow())
    }

    func test_warning_description_when_not_colored_output() {
        environment.shouldOutputBeColoured = false
        let value = PrintableString.Token.warning("test")
        XCTAssertEqual(value.description, "test")
    }

    func test_info_description_when_colored_output() {
        environment.shouldOutputBeColoured = true
        let value = PrintableString.Token.info("test")
        XCTAssertEqual(value.description, "test".lightBlue())
    }

    func test_info_description_when_not_colored_output() {
        environment.shouldOutputBeColoured = false
        let value = PrintableString.Token.info("test")
        XCTAssertEqual(value.description, "test")
    }
}
