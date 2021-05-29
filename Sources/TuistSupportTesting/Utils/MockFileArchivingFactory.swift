import Foundation
import TSCBasic
import TuistSupport

public class MockFileArchivingFactory: FileArchivingFactorying {
    public init() {}

    public var invokedMakeFileArchiver = false
    public var invokedMakeFileArchiverCount = 0
    public var invokedMakeFileArchiverParameters: (paths: [AbsolutePath], Void)?
    public var invokedMakeFileArchiverParametersList = [(paths: [AbsolutePath], Void)]()
    public var stubbedMakeFileArchiverError: Error?
    public var stubbedMakeFileArchiverResult: FileArchiving!

    public func makeFileArchiver(for paths: [AbsolutePath]) throws -> FileArchiving {
        invokedMakeFileArchiver = true
        invokedMakeFileArchiverCount += 1
        invokedMakeFileArchiverParameters = (paths, ())
        invokedMakeFileArchiverParametersList.append((paths, ()))
        if let error = stubbedMakeFileArchiverError {
            throw error
        }
        return stubbedMakeFileArchiverResult
    }

    public var invokedMakeFileUnarchiver = false
    public var invokedMakeFileUnarchiverCount = 0
    public var invokedMakeFileUnarchiverParameters: (path: AbsolutePath, Void)?
    public var invokedMakeFileUnarchiverParametersList = [(path: AbsolutePath, Void)]()
    public var stubbedMakeFileUnarchiverError: Error?
    public var stubbedMakeFileUnarchiverResult: FileUnarchiving!

    public func makeFileUnarchiver(for path: AbsolutePath) throws -> FileUnarchiving {
        invokedMakeFileUnarchiver = true
        invokedMakeFileUnarchiverCount += 1
        invokedMakeFileUnarchiverParameters = (path, ())
        invokedMakeFileUnarchiverParametersList.append((path, ()))
        if let error = stubbedMakeFileUnarchiverError {
            throw error
        }
        return stubbedMakeFileUnarchiverResult
    }
}

public class MockFileArchiver: FileArchiving {
    public init() {}

    public var invokedZip = false
    public var invokedZipCount = 0
    public var invokedZipParameters: (name: String, Void)?
    public var invokedZipParametersList = [(name: String, Void)]()
    public var stubbedZipError: Error?
    public var stubbedZipResult: AbsolutePath!

    public func zip(name: String) throws -> AbsolutePath {
        invokedZip = true
        invokedZipCount += 1
        invokedZipParameters = (name, ())
        invokedZipParametersList.append((name, ()))
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

public class MockFileUnarchiver: FileUnarchiving {
    public init() {}

    public var invokedUnzip = false
    public var invokedUnzipCount = 0
    public var stubbedUnzipError: Error?
    public var stubbedUnzipResult: AbsolutePath!

    public func unzip() throws -> AbsolutePath {
        invokedUnzip = true
        invokedUnzipCount += 1
        if let error = stubbedUnzipError {
            throw error
        }
        return stubbedUnzipResult
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
