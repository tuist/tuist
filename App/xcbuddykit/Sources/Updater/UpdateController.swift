import Foundation
import Sparkle

/// Defines the interface of a controller that handles app updates.
protocol UpdateControlling: AnyObject {
    /// Checks and update from the console.
    /// Intended to be used from the CLI.
    ///
    /// - Parameter context: context.
    /// - Throws: an error if the check and update process fails.
    func checkAndUpdateFromConsole(context: Contexting) throws

    /// Checks and updates from the app.
    ///
    /// - Parameter sender: sender.
    func checkAndUpdateFromApp(sender: Any)
}

/// Default update controller.
public class UpdateController: UpdateControlling {
    /// Constructor.
    public init() {}

    /// Checks and update from the console.
    /// Intended to be used from the CLI.
    ///
    /// - Throws: an error if the check and update process fails.

    /// Checks and update from the console.
    /// Intended to be used from the CLI.
    ///
    /// - Parameter context: context.
    /// - Throws: an error if the check and update process fails.
    func checkAndUpdateFromConsole(context: Contexting) throws {
        let updater = try SPUUpdater.commandLine(context: context)
        updater.checkForUpdates()
        try updater.start()
        RunLoop.current.run()
    }

    /// Checks and updates from the app.
    ///
    /// - Parameter sender: sender.
    public func checkAndUpdateFromApp(sender: Any) {
        let updater = SPUStandardUpdaterController.app
        updater.checkForUpdates(sender)
    }
}
