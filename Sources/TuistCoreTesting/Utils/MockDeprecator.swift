import Foundation
import TuistCore

public final class MockDeprecator: Deprecating {
    public var notifyArgs: [(deprecation: String, suggestion: String)] = []

    public func notify(deprecation: String, suggestion: String) {
        notifyArgs.append((deprecation: deprecation, suggestion: suggestion))
    }
}
