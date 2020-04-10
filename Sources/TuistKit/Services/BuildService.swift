import Basic
import Foundation
import SPMUtility
import TuistSupport

enum BuildServiceError: FatalError {
    // Error description
    var description: String {
        ""
    }

    // Error type
    var type: ErrorType { .abort }
}

final class BuildService {
    func run() throws {
        logger.notice("Command not available yet")
    }
}
