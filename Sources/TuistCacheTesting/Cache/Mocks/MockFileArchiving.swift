import Foundation
import TSCBasic

@testable import TuistCache

public class MockFileArchiver: FileArchiving {
    public init() {}

    public var invokedZip = false
    public var invokedZipCount = 0
    public var invokedZipParameters: (xcframeworkPath: AbsolutePath, Void)?
    public var invokedZipParametersList = [(xcframeworkPath: AbsolutePath, Void)]()
    public var stubbedZipError: Error?
    public var stubbedZipResult: AbsolutePath!

    public func zip(xcframeworkPath: AbsolutePath) throws -> AbsolutePath {
        invokedZip = true
        invokedZipCount += 1
        invokedZipParameters = (xcframeworkPath, ())
        invokedZipParametersList.append((xcframeworkPath, ()))
        if let error = stubbedZipError {
            throw error
        }
        return stubbedZipResult
    }
}
