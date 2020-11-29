import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCartfileContentGenerator: CartfileContentGenerating {
    public init() {}

    var invokedCartfileContent = false
    var invokedCartfileContentCount = 0
    var invokedCartfileContentParameters: [CarthageDependency]?
    var invokedCartfileContentParametersList = [[CarthageDependency]]()
    var cartfileContentStub: (([CarthageDependency]) throws -> String)?

    public func cartfileContent(for dependencies: [CarthageDependency]) throws -> String {
        invokedCartfileContent = true
        invokedCartfileContentCount += 1
        invokedCartfileContentParameters = dependencies
        invokedCartfileContentParametersList.append(dependencies)
        if let stub = cartfileContentStub {
            return try stub(dependencies)
        } else {
            return ""
        }
    }
}
