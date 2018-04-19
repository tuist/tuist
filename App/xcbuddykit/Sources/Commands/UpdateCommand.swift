import Foundation
import Sparkle
import Utility

/// Command that updates the app.
public class UpdateCommand: NSObject, Command, SPUUpdaterDelegate {

    // MARK: - Command
    
    /// Command name.
    public let command = "update"

    /// Command description.
    public let overview = "Updates the app."

    /// Controller used to update the app.
    fileprivate let controller: UpdateControlling

    public required init(parser: ArgumentParser) {
        parser.add(subparser: command, overview: overview)
        controller = UpdateController()
    }
    
    public func run(with _: ArgumentParser.Result) throws {
        try controller.checkAndUpdateFromConsole()
    }
    
    // MARK: - Init
    
    init(controller: UpdateControlling) {
        self.controller = controller
    }
    
}
