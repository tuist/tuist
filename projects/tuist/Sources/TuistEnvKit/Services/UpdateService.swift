import Foundation
import TuistSupport

final class UpdateService {
    /// Updater instance that runs the update.
    private let updater: Updating

    init(updater: Updating = Updater()) {
        self.updater = updater
    }

    func run() throws {
        logger.notice("Checking for updates...", metadata: .section)
        try updater.update()
    }
}
