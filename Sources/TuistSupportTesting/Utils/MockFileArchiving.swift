import Foundation
import TSCBasic
import TuistSupport

public class MockFileArchiverFactory: FileArchiverManufacturing {
    public init() {}

    public var invokedMakeFileArchiver = false
    public var invokedMakeFileArchiverCount = 0
    public var invokedMakeFileArchiverParameters: (path: AbsolutePath, Void)?
    public var invokedMakeFileArchiverParametersList = [(path: AbsolutePath, Void)]()
    public var stubbedMakeFileArchiverResult: FileArchiving = MockFileArchiver()

    public func makeFileArchiver(for path: AbsolutePath) -> FileArchiving {
        invokedMakeFileArchiver = true
        invokedMakeFileArchiverCount += 1
        invokedMakeFileArchiverParameters = (path, ())
        invokedMakeFileArchiverParametersList.append((path, ()))
        return stubbedMakeFileArchiverResult
    }

    public var invokedMakeFileArchiverFor = false
    public var invokedMakeFileArchiverForCount = 0
    public var invokedMakeFileArchiverForParameters: (path: AbsolutePath, fileHandler: FileHandling)?
    public var invokedMakeFileArchiverForParametersList = [(path: AbsolutePath, fileHandler: FileHandling)]()
    public var stubbedMakeFileArchiverForResult: FileArchiving = MockFileArchiver()

    public func makeFileArchiver(for path: AbsolutePath, fileHandler: FileHandling) -> FileArchiving {
        invokedMakeFileArchiverFor = true
        invokedMakeFileArchiverForCount += 1
        invokedMakeFileArchiverForParameters = (path, fileHandler)
        invokedMakeFileArchiverForParametersList.append((path, fileHandler))
        return stubbedMakeFileArchiverForResult
    }
}

public class MockFileArchiver: FileArchiving {
    public var invokedZip = false
    public var invokedZipCount = 0
    public var stubbedZipError: Error?
    public var stubbedZipResult: AbsolutePath!

    public func zip() throws -> AbsolutePath {
        invokedZip = true
        invokedZipCount += 1
        if let error = stubbedZipError {
            throw error
        }
        return stubbedZipResult
    }

    public var invokedDelete = false
    public var invokedDeleteCount = 0
    public var stubbedDeleteError: Error?

    public func delete() throws {
        invokedDelete = true
        invokedDeleteCount += 1
        if let error = stubbedDeleteError {
            throw error
        }
    }
}
