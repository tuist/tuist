import Testing
@testable import TuistKit

struct XCBeautifyArgumentsParserTests {
    let parser = XCBeautifyArgumentsParser()

    @Test
    func noBeautifyArgs() {
        // Given
        let args = ["build", "-scheme", "App"]

        // When
        let result = parser.parse(args)

        // Then
        #expect(result.remaining == args)
        #expect(result.xcbeautify.isEmpty)
    }

    @Test
    func singleBeautifyFlagWithValue() {
        // Given
        let args = ["build", "--xcbeautify-color", "always"]

        // When
        let result = parser.parse(args)

        // Then
        #expect(result.remaining == ["build"])
        #expect(result.xcbeautify == ["--color", "always"])
    }

    @Test
    func singleBeautifyFlagWithoutValue() {
        // Given
        let args = ["--xcbeautify-quiet"]

        // When
        let result = parser.parse(args)

        // Then
        #expect(result.remaining.isEmpty)
        #expect(result.xcbeautify == ["--quiet"])
    }

    @Test
    func beautifyFlagFollowedByFlag() {
        // Given
        let args = ["--xcbeautify-color", "--other-flag"]

        // When
        let result = parser.parse(args)

        // Then
        #expect(result.remaining == ["--other-flag"])
        #expect(result.xcbeautify == ["--color"])
    }

    @Test
    func mixedArgs() {
        // Given
        let args = [
            "test",
            "--xcbeautify-color", "always",
            "--xcbeautify-quiet",
            "-scheme", "App",
        ]

        // When
        let result = parser.parse(args)

        // Then
        #expect(result.remaining == ["test", "-scheme", "App"])
        #expect(result.xcbeautify == ["--color", "always", "--quiet"])
    }

    @Test
    func beautifyFlagAtEnd() {
        // Given
        let args = ["build", "--xcbeautify-verbose"]

        // When
        let result = parser.parse(args)

        // Then
        #expect(result.remaining == ["build"])
        #expect(result.xcbeautify == ["--verbose"])
    }
}
