import Foundation
import TSCBasic
@testable import TuistLoader

public final class MockSetupLocator: SetupLocating {
    var invokedLocate = false
    var invokedLocateCount = 0
    var invokedLocateParameters: (path: AbsolutePath, Void)?
    var invokedLocateParametersList = [(path: AbsolutePath, Void)]()
    var stubbedLocateResult: AbsolutePath!

    public func locate(at path: AbsolutePath) -> AbsolutePath? {
        invokedLocate = true
        invokedLocateCount += 1
        invokedLocateParameters = (path, ())
        invokedLocateParametersList.append((path, ()))
        return stubbedLocateResult
    }
}
