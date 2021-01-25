import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockCartfileContentGenerator: CartfileContentGenerating {
    public init() {}

    var invokedCartfileContent = false
    var invokedCartfileContentCount = 0
    var invokedCartfileContentParameters: [CarthageDependency]?
    var invokedCartfileContentParametersList = [[CarthageDependency]]()
    var cartfileContentStub: (([CarthageDependency]) -> String)?

    public func cartfileContent(for dependencies: [CarthageDependency]) -> String {
        invokedCartfileContent = true
        invokedCartfileContentCount += 1
        invokedCartfileContentParameters = dependencies
        invokedCartfileContentParametersList.append(dependencies)
        if let stub = cartfileContentStub {
            return stub(dependencies)
        } else {
            return ""
        }
    }
}
