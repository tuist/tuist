import Basic
import Foundation
import TuistSupport

final class VersionService {
    func run() throws {
        logger.notice("\(Constants.version)")
    }
}
