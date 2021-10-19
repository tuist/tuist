import Foundation
@testable import TuistAnalytics

class MockCloudAnalyticsResourceFactory: CloudAnalyticsResourceFactorying {
    var invokedCreate = false
    var invokedCreateCount = 0
    var invokedCreateParameters: (commandEvent: CommandEvent, Void)?
    var invokedCreateParametersList = [(commandEvent: CommandEvent, Void)]()
    var stubbedCreateError: Error?
    var stubbedCreateResult: CloudAnalyticsCreateResource!

    func create(commandEvent: CommandEvent) throws -> CloudAnalyticsCreateResource {
        invokedCreate = true
        invokedCreateCount += 1
        invokedCreateParameters = (commandEvent, ())
        invokedCreateParametersList.append((commandEvent, ()))
        if let error = stubbedCreateError {
            throw error
        }
        return stubbedCreateResult
    }
}
