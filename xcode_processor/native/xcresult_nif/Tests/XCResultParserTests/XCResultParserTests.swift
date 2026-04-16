import Foundation
import Path
import Testing
@testable import XCResultParser

struct XCResultParserTests {
    let parser = XCResultParser()

    private func fixturePath(_ name: String) throws -> AbsolutePath {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try AbsolutePath(validating: url.path)
    }

    @Test
    func parse_populatesRunDestinationsFromTheXcresultDevicesArray() async throws {
        let xcresult = try fixturePath("test-with-arguments.xcresult")

        let summary = try await parser.parse(path: xcresult, rootDirectory: nil)
        let destinations = try #require(summary?.runDestinations)

        #expect(destinations.count == 1)
        #expect(destinations[0].name == "iPhone Air")
        #expect(destinations[0].platform == "iOS Simulator")
        #expect(destinations[0].osVersion == "26.4")
    }
}
