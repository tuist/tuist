import Foundation
import Testing

@testable import ProjectDescription

struct PlatformTests {
    @Test func toJSON() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let subjects: [(subject: [Platform], json: String)] = [
            ([.iOS], "[\"ios\"]"),
            ([.macOS], "[\"macos\"]"),
            ([.watchOS], "[\"watchos\"]"),
            ([.tvOS], "[\"tvos\"]"),
        ]

        for (subject, json) in subjects {
            let decoded = try decoder.decode([Platform].self, from: json.data(using: .utf8)!)
            let jsonData = try encoder.encode(decoded)
            let subjectData = try encoder.encode(subject)
            #expect(jsonData == subjectData)
        }
    }
}
