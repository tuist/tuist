import Foundation
import RxSwift
import TSCBasic
import TuistCache

public final class MockFileUploader: FileUploading {
    public init() {}

    public var invokedUpload = false
    public var invokedUploadCount = 0
    public var invokedUploadParameters: (file: AbsolutePath, hash: String, url: URL)?
    public var invokedUploadParametersList = [(file: AbsolutePath, hash: String, url: URL)]()
    public var stubbedUploadResult: Single<Bool> = Single.just(true)

    public func upload(file: AbsolutePath, hash: String, to url: URL) -> Single<Bool> {
        invokedUpload = true
        invokedUploadCount += 1
        invokedUploadParameters = (file, hash, url)
        invokedUploadParametersList.append((file, hash, url))
        return stubbedUploadResult
    }
}
