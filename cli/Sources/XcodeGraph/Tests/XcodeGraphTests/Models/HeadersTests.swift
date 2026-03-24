import Foundation
import Path
import Testing
@testable import XcodeGraph

struct HeadersTests {
    @Test func codable() throws {
        // Given
        let subject = Headers(
            public: [
                try AbsolutePath(validating: "/path/to/public/header"),
            ],
            private: [
                try AbsolutePath(validating: "/path/to/private/header"),
            ],
            project: [
                try AbsolutePath(validating: "/path/to/project/header"),
            ]
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Headers.self, from: data)
        #expect(subject == decoded)
    }
}
