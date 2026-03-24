import Foundation
import Testing
@testable import XcodeGraph

struct ArgumentsTests {
    @Test func codable() throws {
        // Given
        let subject = Arguments(
            environmentVariables: [
                "key": EnvironmentVariable(value: "value", isEnabled: true),
            ],
            launchArguments: [
                .init(
                    name: "name",
                    isEnabled: true
                ),
            ]
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Arguments.self, from: data)
        #expect(subject == decoded)
    }
}
