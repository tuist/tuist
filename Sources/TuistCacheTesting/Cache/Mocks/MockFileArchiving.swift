import Foundation
import TSCBasic

@testable import TuistCache

public class MockFileArchiver: FileArchiving {
    public init() {}

    public var invokedZip = false
    public var invokedZipCount = 0
    public var invokedZipParameters: (xcframeworkPath: AbsolutePath, hash: String)?
    public var invokedZipParametersList = [(xcframeworkPath: AbsolutePath, hash: String)]()
    public var stubbedZipError: Error?
    public var stubbedZipResult: AbsolutePath!

    public func zip(xcframeworkPath: AbsolutePath, hash: String) throws -> AbsolutePath {
        invokedZip = true
        invokedZipCount += 1
        invokedZipParameters = (xcframeworkPath, hash)
        invokedZipParametersList.append((xcframeworkPath, hash))
        if let error = stubbedZipError {
            throw error
        }
        return stubbedZipResult
    }
}
