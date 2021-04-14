import Foundation
import TSCBasic
import TuistSupport

final class VersionService {
    func run() throws {
        logger.notice("\(Constants.version)")
    }
}
