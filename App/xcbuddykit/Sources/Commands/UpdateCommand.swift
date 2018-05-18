import Foundation
import Sparkle
import Utility

/// Command that updates the app.
public class UpdateCommand: NSObject, Command, SPUUpdaterDelegate {

    // MARK: - Command

    /// Command name.
    public static let command = "update"

    /// Command description.
    public static let overview = "Updates the app."

    /// Context.
    fileprivate let context: CommandsContexting

    /// Controller used to update the app.
    fileprivate let controller: UpdateControlling

    public required init(parser: ArgumentParser) {
        parser.add(subparser: UpdateCommand.command, overview: UpdateCommand.overview)
        controller = UpdateController()
        context = CommandsContext()
    }

    public func run(with _: ArgumentParser.Result) throws {
        try controller.checkAndUpdateFromConsole(context: context)
    }

    // MARK: - Init

    init(controller: UpdateControlling,
         context: CommandsContexting) {
        self.controller = controller
        self.context = context
    }
}
