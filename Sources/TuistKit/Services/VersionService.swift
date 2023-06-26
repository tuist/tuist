import Foundation
import TSCBasic
import TuistSupport

public final class VersionService {
    public func run() throws {
        logger.notice("\(Constants.version)")
    }
}
