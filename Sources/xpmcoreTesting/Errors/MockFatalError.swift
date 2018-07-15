import Foundation
import xpmcore

public final class MockFatalError: FatalError {
    public let type: ErrorType
    public let description: String

    init(type: ErrorType = .abort, description: String = "test") {
        self.type = type
        self.description = description
    }
}
