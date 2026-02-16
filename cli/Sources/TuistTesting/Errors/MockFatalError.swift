import Foundation
import TuistLogging
import TuistSupport

public struct MockFatalError: FatalError {
    public let type: ErrorType
    public let description: String

    init(type: ErrorType = .abort, description: String = "test") {
        self.type = type
        self.description = description
    }
}
