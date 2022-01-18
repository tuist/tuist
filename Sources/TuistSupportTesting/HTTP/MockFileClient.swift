import Foundation
import TSCBasic
import TuistSupport

// swiftlint:disable large_tuple

public final class MockFileClient: FileClienting {
    public init() {}

    public var invokedUpload = false
    public var invokedUploadCount = 0
    public var invokedUploadParameters: (file: AbsolutePath, hash: String, url: URL)?
    public var invokedUploadParametersList = [(file: AbsolutePath, hash: String, url: URL)]()
    public var stubbedUploadResult = true
    public var stubbedUploadError: Error!

    public func upload(file: AbsolutePath, hash: String, to url: URL) async throws -> Bool {
        invokedUpload = true
        invokedUploadCount += 1
        invokedUploadParameters = (file, hash, url)
        invokedUploadParametersList.append((file, hash, url))
        if let stubbedUploadError = stubbedUploadError {
            throw stubbedUploadError
        }
        return stubbedUploadResult
    }

    public var invokedDownload = false
    public var invokedDownloadCount = 0
    public var invokedDownloadParameters: (url: URL, Void)?
    public var invokedDownloadParametersList = [(url: URL, Void)]()
    public var stubbedDownloadResult: AbsolutePath!

    public func download(url: URL) async throws -> AbsolutePath {
        invokedDownload = true
        invokedDownloadCount += 1
        invokedDownloadParameters = (url, ())
        invokedDownloadParametersList.append((url, ()))
        return stubbedDownloadResult
    }
}

// swiftlint:enable large_tuple
