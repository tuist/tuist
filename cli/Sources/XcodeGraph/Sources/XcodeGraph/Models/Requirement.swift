import Foundation

public enum Requirement: Equatable, Hashable, Codable, Sendable {
    case upToNextMajor(String)
    case upToNextMinor(String)
    case range(from: String, to: String)
    case exact(String)
    case branch(String)
    case revision(String)
}
