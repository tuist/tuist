import Foundation
import RxSwift
import TSCBasic
import TuistSupport

// swiftlint:disable large_tuple

public final class MockFileClient: FileClienting {
    public init() {}

    public typealias UploadParameters = (file: AbsolutePath, hash: String, url: URL, additionalHeaders: [String: String]?)
    public var invokedUpload = false
    public var invokedUploadCount = 0
    public var invokedUploadParameters: UploadParameters?
    public var invokedUploadParametersList = [UploadParameters]()
    public var stubbedUploadResult: Single<Bool> = Single.just(true)

    public func upload(file: AbsolutePath, hash: String, to url: URL, additionalHeaders: [String: String]?) -> Single<Bool> {
        invokedUpload = true
        invokedUploadCount += 1
        invokedUploadParameters = (file, hash, url, additionalHeaders)
        invokedUploadParametersList.append((file, hash, url, additionalHeaders))
        return stubbedUploadResult
    }

    public var invokedDownload = false
    public var invokedDownloadCount = 0
    public var invokedDownloadParameters: (url: URL, Void)?
    public var invokedDownloadParametersList = [(url: URL, Void)]()
    public var stubbedDownloadResult: Single<AbsolutePath>!

    public func download(url: URL) -> Single<AbsolutePath> {
        invokedDownload = true
        invokedDownloadCount += 1
        invokedDownloadParameters = (url, ())
        invokedDownloadParametersList.append((url, ()))
        return stubbedDownloadResult
    }
}

// swiftlint:enable large_tuple
