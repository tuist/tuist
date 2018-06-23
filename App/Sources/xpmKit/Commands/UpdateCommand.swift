import Foundation
import Utility

/// Command that updates the app.
public class UpdateCommand: NSObject, Command {

    // MARK: - Command

    /// Command name.
    public static let command = "update"

    /// Command description.
    public static let overview = "Updates the app."

    /// Context.
    fileprivate let context: CommandsContexting

    public required init(parser: ArgumentParser) {
        parser.add(subparser: UpdateCommand.command, overview: UpdateCommand.overview)
        context = CommandsContext()
    }

    public func run(with _: ArgumentParser.Result) throws {
    }
}
