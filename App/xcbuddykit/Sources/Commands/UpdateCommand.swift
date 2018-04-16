import Foundation
import Sparkle
import SwiftCLI

/// Checks if there are updates and updates the app.
public class UpdateCommand: NSObject, Command, SPUUpdaterDelegate {
    /// Name of the command.
    public let name: String = "update"

    /// Description of the command for the cli.
    public let shortDescription = "Updates the app"

    /// Update controller.
    fileprivate let controller: UpdateControlling

    public convenience override init() {
        self.init(controller: UpdateController())
    }

    /// Default constructor.
    init(controller: UpdateControlling) {
        self.controller = controller
    }

    /// Executes the command, checking if there are updates, and updating in case there are.
    ///
    /// - Throws: an error if something goes wrong.
    public func execute() throws {
        try controller.checkAndUpdateFromConsole()
    }
}
