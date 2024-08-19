import TuistSupportTesting
import XCTest
@testable import TuistSupport

class UserInputReaderTests: TuistUnitTestCase {
    func test_read_int_valid_input() {
        // Given
        var fakeReadLine = StringReader(input: "0")
        let reader: UserInputReader = .init { _ in
            fakeReadLine.readLine()
        }

        // When
        let result = reader.readInt(asking: "prompt", maxValueAllowed: 1)

        // Then
        XCTAssertEqual(result, Int(fakeReadLine.input))
    }

    func test_read_int_after_incorrect_inputs() {
        // Given
        var fakeReadLine = StringReader(input: "a21")
        let reader: UserInputReader = .init { _ in
            fakeReadLine.readLine()
        }

        // When
        let result = reader.readInt(asking: "prompt", maxValueAllowed: 2)

        // Then
        XCTAssertEqual(result, Int(String(fakeReadLine.input.last!)))
    }

    func test_read_string() {
        // Given
        let reader: UserInputReader = .init { _ in
            return "string-value"
        }

        // When
        let result = reader.readString(asking: "prompt")

        // Then
        XCTAssertEqual(result, "string-value")
    }

    struct Value: Equatable {
        let name: String
    }

    func test_read_value_when_only_value_provided() throws {
        // Given
        let reader: UserInputReader = .init { _ in
            XCTFail("Value should be returned without reading a line")
            return "string-value"
        }
        let value = Value(name: "value-one")

        // When
        let got = try reader.readValue(
            asking: "Choose value:",
            values: [value],
            valueDescription: \.name
        )

        // Then
        XCTAssertEqual(got, value)
    }

    func test_read_value_when_no_values_provided() throws {
        // Given
        let reader: UserInputReader = .init { _ in
            XCTFail("Value should be returned without reading a line")
            return "string-value"
        }
        let value = Value(name: "value-one")

        // When / Then
        XCTAssertThrowsSpecific(
            try reader.readValue(
                asking: "Choose value:",
                values: [Value](),
                valueDescription: \.name
            ),
            UserInputReaderError.noValuesProvided("Choose value:")
        )
    }

    func test_read_value_when_multiple_values_provided() throws {
        // Given
        var fakeReadLine = StringReader(input: "1")
        let reader: UserInputReader = .init { _ in
            fakeReadLine.readLine()
        }
        let valueOne = Value(name: "value-one")
        let valueTwo = Value(name: "value-two")

        // When
        let got = try reader.readValue(
            asking: "Choose value:",
            values: [valueOne, valueTwo],
            valueDescription: \.name
        )

        // Then
        XCTAssertEqual(got, valueTwo)
        XCTAssertStandardOutput(
            pattern: """
            Choose value:
            \t0: value-one
            \t1: value-two
            """
        )
    }
}

// Custom string reader to simulate user input
private struct StringReader {
    let input: String
    var index: String.Index

    init(input: String) {
        self.input = input
        index = input.startIndex
    }

    mutating func readLine() -> String? {
        guard index < input.endIndex else { return nil }
        defer { index = input.index(after: index) }
        return String(input[index...])
    }
}
