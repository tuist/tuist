import Foundation
import TuistSupport

/// The class that conforms this protocol exposes an interface for interacting with the user settings.
protocol SettingsControlling: AnyObject {
    /// It fetches the current settings.
    ///
    /// - Returns: settings.
    /// - Throws: an error if the settings cannot be fetched.
    func settings() throws -> Settings

    /// Stores the settings.
    ///
    /// - Parameter settings: settings to be stored.
    /// - Throws: an error if the saving fails.
    func set(settings: Settings) throws
}

/// Controller to manage user settings.
class SettingsController: SettingsControlling {
    /// It fetches the current settings.
    ///
    /// - Returns: settings.
    /// - Throws: an error if the settings cannot be fetched.
    func settings() throws -> Settings {
        let path = Environment.shared.settingsPath
        if !FileHandler.shared.exists(path) { return Settings() }
        let data = try Data(contentsOf: URL(fileURLWithPath: path.pathString))
        let decoder = JSONDecoder()
        return try decoder.decode(Settings.self, from: data)
    }

    /// Stores the settings.
    ///
    /// - Parameter settings: settings to be stored.
    /// - Throws: an error if the saving fails.
    func set(settings: Settings) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        let path = Environment.shared.settingsPath
        if FileHandler.shared.exists(path) { try FileHandler.shared.delete(path) }
        let url = URL(fileURLWithPath: path.pathString)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }
}
