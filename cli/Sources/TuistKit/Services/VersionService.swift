import Foundation
import Logging
import Path
import TuistConstants
import TuistLogging
import TuistSupport

final class VersionService {
    func run() throws {
        let version: String = Constants.version
        Logger.current.notice("\(version)")
    }
}
