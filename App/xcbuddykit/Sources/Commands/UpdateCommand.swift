import Foundation
import Sparkle
import Utility

public class UpdateCommand: NSObject, Command, SPUUpdaterDelegate {
    
    public let command = "update"
    public let overview = "Updates the app."
    fileprivate let controller: UpdateControlling
    
    required public init(parser: ArgumentParser) {
        parser.add(subparser: command, overview: overview)
        self.controller = UpdateController()
    }
    
    init(controller: UpdateControlling) {
        self.controller = controller
    }
    
    public func run(with arguments: ArgumentParser.Result) throws {
        try controller.checkAndUpdateFromConsole()
    }
    
}
