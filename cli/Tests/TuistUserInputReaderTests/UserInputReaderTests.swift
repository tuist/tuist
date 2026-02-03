import Testing

@testable import TuistUserInputReader

struct UserInputReaderTests {
    @Test func readIntValidInput() {
        // Given
        var fakeReadLine = StringReader(input: "0")
        let reader: UserInputReader = .init { _ in
            fakeReadLine.readLine()
        }

        // When
        let result = reader.readInt(asking: "prompt", maxValueAllowed: 1)

        // Then
        #expect(result == Int(fakeReadLine.input))
    }

    @Test func readIntAfterIncorrectInputs() {
        // Given
        var fakeReadLine = StringReader(input: "a21")
        let reader: UserInputReader = .init { _ in
            fakeReadLine.readLine()
        }

        // When
        let result = reader.readInt(asking: "prompt", maxValueAllowed: 2)

        // Then
        #expect(result == Int(String(fakeReadLine.input.last!)))
    }

    @Test func readString() {
        // Given
        let reader: UserInputReader = .init { _ in
            return "string-value"
        }

        // When
        let result = reader.readString(asking: "prompt")

        // Then
        #expect(result == "string-value")
    }

    struct Value: Equatable {
        let name: String
    }

    @Test func readValueWhenOnlyValueProvided() throws {
        // Given
        let reader: UserInputReader = .init { _ in
            Issue.record("Value should be returned without reading a line")
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
        #expect(got == value)
    }

    @Test func readValueWhenNoValuesProvided() throws {
        // Given
        let reader: UserInputReader = .init { _ in
            Issue.record("Value should be returned without reading a line")
            return "string-value"
        }

        // When / Then
        #expect(throws: UserInputReaderError.noValuesProvided("Choose value:")) {
            try reader.readValue(
                asking: "Choose value:",
                values: [Value](),
                valueDescription: \.name
            )
        }
    }

    @Test func readValueWhenMultipleValuesProvided() throws {
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
        #expect(got == valueTwo)
    }
}

/// Custom string reader to simulate user input.
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
