import Foundation
import Path
#if os(macOS)
    import TuistHTTP
#endif
import TuistSupport

// swiftlint:disable large_tuple

#if os(macOS)
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
            if let stubbedUploadError {
                throw stubbedUploadError
            }
            return stubbedUploadResult
        }

        public var invokedDownload = false
        public var invokedDownloadCount = 0
        public var invokedDownloadParameters: (url: URL, destination: AbsolutePath)?
        public var invokedDownloadParametersList = [(url: URL, destination: AbsolutePath)]()
        public var stubbedDownloadResult: AbsolutePath!

        public func download(url: URL, to destination: AbsolutePath) async throws -> AbsolutePath {
            invokedDownload = true
            invokedDownloadCount += 1
            invokedDownloadParameters = (url, destination)
            invokedDownloadParametersList.append((url, destination))
            return stubbedDownloadResult ?? destination
        }
    }

    // swiftlint:enable large_tuple
#endif
