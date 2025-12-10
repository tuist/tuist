import Foundation
import Testing

@testable import TuistOIDC

struct OIDCTokenFetcherTests {
    @Test
    func fetchToken_throws_invalidTokenRequestURL_when_url_cannot_be_parsed() async throws {
        // Given
        let subject = OIDCTokenFetcher()

        // When / Then
        // A URL with spaces that cannot be parsed by URLComponents
        await #expect(throws: OIDCTokenFetcherError.invalidTokenRequestURL("http://[invalid")) {
            try await subject.fetchToken(
                requestURL: "http://[invalid",
                requestToken: "token",
                audience: "tuist"
            )
        }
    }
}
