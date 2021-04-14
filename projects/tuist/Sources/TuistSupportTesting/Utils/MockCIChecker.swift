import Foundation
import TuistSupport

public final class MockCIChecker: CIChecking {
    var isCIStub: Bool = false

    public func isCI() -> Bool {
        isCIStub
    }
}
