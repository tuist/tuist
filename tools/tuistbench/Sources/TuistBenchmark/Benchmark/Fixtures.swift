import Foundation

struct Fixtures: Decodable {
    /// Paths to fixtures
    /// - Note: can be Absolute or relative to current working directory
    var paths: [String]
}
