import Foundation
import Testing

@testable import TuistHAR

struct HARTests {
    @Test
    func encode_decodesCorrectly() throws {
        // Given
        let entry = HAR.Entry(
            startedDateTime: Date(timeIntervalSince1970: 1_700_000_000),
            time: 150,
            request: HAR.Request(
                method: "GET",
                url: "https://api.example.com/users/42",
                headers: [
                    HAR.Header(name: "Accept", value: "application/json"),
                ],
                queryString: [
                    HAR.QueryParameter(name: "page", value: "1"),
                ]
            ),
            response: HAR.Response(
                status: 200,
                statusText: "OK",
                headers: [
                    HAR.Header(name: "Content-Type", value: "application/json"),
                ],
                content: HAR.Content(
                    size: 52,
                    mimeType: "application/json",
                    text: "{\"id\":42,\"name\":\"Alice\"}"
                )
            ),
            timings: HAR.Timings(
                send: 0,
                wait: 150,
                receive: 0
            )
        )

        let log = HAR.Log(
            creator: HAR.Creator(name: "Tuist", version: "1.0.0"),
            entries: [entry]
        )

        // When
        let encoded = try HAR.encode(log)
        let decoded = try HAR.decode(from: encoded)

        // Then
        #expect(decoded.version == "1.2")
        #expect(decoded.creator.name == "Tuist")
        #expect(decoded.creator.version == "1.0.0")
        #expect(decoded.entries.count == 1)

        let decodedEntry = decoded.entries[0]
        #expect(decodedEntry.request.method == "GET")
        #expect(decodedEntry.request.url == "https://api.example.com/users/42")
        #expect(decodedEntry.response.status == 200)
        #expect(decodedEntry.response.content.text == "{\"id\":42,\"name\":\"Alice\"}")
    }

    @Test
    func encode_producesValidJSON() throws {
        // Given
        let log = HAR.Log(
            creator: HAR.Creator(name: "Tuist", version: "1.0.0"),
            entries: []
        )

        // When
        let encoded = try HAR.encode(log)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        // Then
        #expect(json != nil)
        #expect(json?["log"] != nil)
    }
}
