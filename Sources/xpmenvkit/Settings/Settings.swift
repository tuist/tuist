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
    init(lastTimeUpdatesChecked _: Date? = nil,
         canaryReference _: String? = nil) {
        lastTimeUpdatesChecked = nil
        canaryReference = nil
    }

    // MARK: - Equatable

    static func == (lhs: Settings, rhs: Settings) -> Bool {
        return lhs.lastTimeUpdatesChecked == rhs.lastTimeUpdatesChecked &&
            lhs.canaryReference == rhs.canaryReference
    }
}
