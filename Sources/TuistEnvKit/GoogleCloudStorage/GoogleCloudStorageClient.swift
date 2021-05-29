import Foundation
import RxSwift
import struct TSCUtility.Version
import TuistSupport

protocol GoogleCloudStorageClienting {
    /// Returns a single that returns the latest version of Tuist that is available.
    func latestVersion() -> Single<TSCUtility.Version>

    /// Returns the URL to return the latest tuistenv.zip
    func latestTuistEnvBundleURL() -> Foundation.URL

    /// Returns an observable that returns the URL to download the given version.
    /// If the version does not exist, it returns nil.
    /// - Parameter version: Version whose URL will be returned.
    func tuistBundleURL(version: String) -> Observable<Foundation.URL?>
}

enum GoogleCloudStorageClientError: FatalError, Equatable {
    case invalidEncoding(url: Foundation.URL, expectedEncoding: String)
    case invalidVersionFormat(String)

    var type: ErrorType {
        switch self {
        case .invalidEncoding:
            return .bug
        case .invalidVersionFormat:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .invalidEncoding(url, expectedEncoding):
            return "Expected '\(url.absoluteString)' to have '\(expectedEncoding)' encoding"
        case let .invalidVersionFormat(version):
            return "Expected '\(version)' to follow the semver format"
        }
    }
}

public final class GoogleCloudStorageClient: GoogleCloudStorageClienting {
    // MARK: - Attributes

    /// Instance to send HTTP requests.
    let urlSessionScheduler: URLSessionScheduling

    init(urlSessionScheduler: URLSessionScheduling = URLSessionScheduler()) {
        self.urlSessionScheduler = urlSessionScheduler
    }

    func latestTuistEnvBundleURL() -> Foundation.URL {
        GoogleCloudStorageClient.url(releasesPath: "latest/tuistenv.zip")
    }

    func tuistBundleURL(version: String) -> Observable<Foundation.URL?> {
        let releaseURL = GoogleCloudStorageClient.url(releasesPath: "\(version)/tuist.zip")
        var releaseRequest = URLRequest(url: releaseURL)
        releaseRequest.httpMethod = "HEAD"
        let releaseSingle = urlSessionScheduler.single(request: releaseRequest)

        let buildURL = GoogleCloudStorageClient.url(buildsPath: "\(version).zip")
        var buildRequest = URLRequest(url: buildURL)
        buildRequest.httpMethod = "HEAD"
        let buildSingle = urlSessionScheduler.single(request: buildRequest)

        return releaseSingle
            /// Try to get the release from the releases bucket
            .map { _ in releaseURL }
            /// Otherwise we try to get it from the builds bucket (where builds from commits live)
            .catchError { _ in buildSingle.map { _ in buildURL } }
            .catchErrorJustReturn(nil)
            .asObservable()
    }

    func latestVersion() -> Single<Version> {
        let request = GoogleCloudStorageClient.releasesRequest(path: "latest/version")
        return urlSessionScheduler.single(request: request)
            .map { data in
                if let string = String(data: data, encoding: .utf8) {
                    if let version = Version(string: string) {
                        return version
                    } else {
                        throw GoogleCloudStorageClientError.invalidVersionFormat(string)
                    }
                } else {
                    throw GoogleCloudStorageClientError.invalidEncoding(url: request.url!, expectedEncoding: "UTF8")
                }
            }
    }

    static func releasesRequest(path: String) -> URLRequest {
        var request = URLRequest(url: url(releasesPath: path))
        request.httpMethod = "GET"
        return request
    }

    static func url(buildsPath path: String) -> Foundation.URL {
        var components = URLComponents(string: "https://storage.googleapis.com")!
        components.path = "/tuist-builds/\(path)"
        return components.url!
    }

    static func url(releasesPath path: String) -> Foundation.URL {
        var components = URLComponents(string: "https://storage.googleapis.com")!
        components.path = "/tuist-releases/\(path)"
        return components.url!
    }
}
