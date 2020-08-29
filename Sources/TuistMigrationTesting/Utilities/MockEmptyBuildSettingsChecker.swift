import Foundation
import TSCBasic
import TuistMigration

public class MockEmptyBuildSettingsChecker: EmptyBuildSettingsChecking {
    public init() {}

    public var invokedCheck = false
    public var invokedCheckCount = 0
    public var invokedCheckParameters: (xcodeprojPath: AbsolutePath, targetName: String?)?
    public var invokedCheckParametersList = [(xcodeprojPath: AbsolutePath, targetName: String?)]()
    public var stubbedCheckError: Error?

    public func check(xcodeprojPath: AbsolutePath, targetName: String?) throws {
        invokedCheck = true
        invokedCheckCount += 1
        invokedCheckParameters = (xcodeprojPath, targetName)
        invokedCheckParametersList.append((xcodeprojPath, targetName))
        if let error = stubbedCheckError {
            throw error
        }
    }
}
