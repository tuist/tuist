import Foundation

/// Settings
class Settings: Codable, Equatable {

    // MARK: - Attributes

    /// Last time updates were checked
    var lastTimeUpdatesChecked: Date?

    /// Environment canary reference.
    var canaryReference: String?

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case lastTimeUpdatesChecked = "last_time_updates_checked"
        case canaryReference = "canary_reference"
    }

    // MARK: - Init

    /// Initializes the settings instance.
    ///
    /// - Parameters:
    ///   - lastTimeUpdatesChecked: Last time updates were checked.
    ///   - canaryReference: Environment canary reference.
    init(lastTimeUpdatesChecked: Date? = nil,
         canaryReference: String? = nil) {
        self.lastTimeUpdatesChecked = lastTimeUpdatesChecked
        self.canaryReference = canaryReference
    }

    // MARK: - Equatable

    static func == (lhs: Settings, rhs: Settings) -> Bool {
        return lhs.lastTimeUpdatesChecked == rhs.lastTimeUpdatesChecked &&
            lhs.canaryReference == rhs.canaryReference
    }
}
