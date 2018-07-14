import Foundation
import xpmcore

/// Protocol that represents a controller for accessing the user settings.
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
        let data = try Data(contentsOf: URL(fileURLWithPath: path.asString))
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
        let url = URL(fileURLWithPath: path.asString)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }
}
