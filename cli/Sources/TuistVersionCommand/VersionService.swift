import Foundation
import TuistConstants
import TuistLogging

final class VersionService {
    func run() throws {
        let version: String = Constants.version
        Logger.current.notice("\(version)")
    }
}
