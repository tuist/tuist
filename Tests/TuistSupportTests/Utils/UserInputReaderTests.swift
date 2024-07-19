import XCTest
@testable import TuistSupport

class UserInputReaderTests: XCTestCase {
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
