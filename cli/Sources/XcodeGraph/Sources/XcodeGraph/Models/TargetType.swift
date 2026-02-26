public enum TargetType: Codable, Hashable, Equatable, Sendable {
    /// A target is local when it hasn't been resolved and pulled by a package manager (e.g., SPM).
    case local
    /// A target is remote, when it has been resolved and pulled by a package manager (e.g., SwiftPM).
    case remote
}
