import Foundation
import TuistCore

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
    // MARK: - Attributes

    /// Environment controller.
    let environmentController: EnvironmentControlling

    /// File handler.
    let fileHandler: FileHandling

    /// Default constructor.
    ///
    /// - Parameter environmentController: environment controller used to get the directory where
    ///   the settings will be stored.
    /// - Parameter fileHandler: file handler.
    init(environmentController: EnvironmentControlling = EnvironmentController(),
         fileHandler: FileHandling = FileHandler()) {
        self.environmentController = environmentController
        self.fileHandler = fileHandler
    }

    /// It fetches the current settings.
    ///
    /// - Returns: settings.
    /// - Throws: an error if the settings cannot be fetched.
    func settings() throws -> Settings {
        let path = environmentController.settingsPath
        if !fileHandler.exists(path) { return Settings() }
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
        let path = environmentController.settingsPath
        if fileHandler.exists(path) { try fileHandler.delete(path) }
        let url = URL(fileURLWithPath: path.pathString)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }
}
