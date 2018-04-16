import Foundation
import Sparkle

protocol UpdateControlling: AnyObject {
    func checkAndUpdateFromConsole() throws
    func checkAndUpdateFromApp(sender: Any)
}

class UpdateController: UpdateControlling {
    init() {}

    func checkAndUpdateFromConsole() throws {
        let updater = SPUUpdater.commandLine
        updater.checkForUpdates()
        try updater.start()
        RunLoop.current.run()
    }

    func checkAndUpdateFromApp(sender: Any) {
        let updater = SPUStandardUpdaterController.app
        updater.checkForUpdates(sender)
    }
}
