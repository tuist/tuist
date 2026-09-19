import Foundation
import Path
import Testing
import TuistSupport
import TuistTestSupport

public enum SwiftTestingHelper {
    public static func fixturePath(path: RelativePath) -> AbsolutePath {
        TestPaths.fixturesDirectory.appending(path)
    }
}

/// Checks that a value can be encoded and decoded, and that the result equals the original.
/// Use with #expect: `#expect(try isCodableRoundTripable(value))`
public func isCodableRoundTripable<C: Codable & Equatable>(_ subject: C) throws -> Bool {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    encoder.outputFormatting = .prettyPrinted

    let data = try encoder.encode(subject)
    let decoded = try decoder.decode(C.self, from: data)

    return subject == decoded
}
