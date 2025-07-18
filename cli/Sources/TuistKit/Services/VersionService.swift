import Foundation
import Logging
import Path
import TuistSupport

final class VersionService {
    func run() throws {
        Logger.current.notice("\(Constants.version)")
    }
}
