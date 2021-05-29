import Foundation

/// Settings
class Settings: Codable, Equatable {
    // MARK: - Init

    /// Initializes the settings instance.
    init() {}

    // MARK: - Equatable

    /// Compares two instances of Settings.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are equal.
    static func == (_: Settings, _: Settings) -> Bool {
        true
    }
}
