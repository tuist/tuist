import TSCBasic
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class TextTableTests: TuistUnitTestCase {
    func test_renders_data() throws {
        // Given
        let columns = [
            "Key 1  0    ",
            "Key 2  1    ",
            "Key 3  2    ",
        ]
        let expectedOutput = """
        Key    Value
        ─────  ─────
        \(columns.joined(separator: "\n"))

        """

        let table = TextTable<Record> { [
            TextTable.Column(title: "Key", value: $0.key),
            TextTable.Column(title: "Value", value: $0.value),
        ] }

        let data = [
            Record(key: "Key 1", value: 0),
            Record(key: "Key 2", value: 1),
            Record(key: "Key 3", value: 2),
        ]

        // When
        let rendered = table.render(data)

        // Then
        XCTAssertTrue(expectedOutput == rendered)
    }

    func test_renders_empty_string_when_data_is_empty() throws {
        // Given
        let table = TextTable<Record> { [
            TextTable.Column(title: "Key", value: $0.key),
            TextTable.Column(title: "Value", value: $0.value),
        ] }

        // When
        let rendered = table.render([])

        // Then
        XCTAssertTrue(rendered.isEmpty)
    }
}

private struct Record {
    let key: String
    let value: Int
}
