import Foundation
import RxSwift
import SPMUtility
import TuistSupport

protocol GoogleCloudStorageClienting {
    /// Returns a single that returns the latest version of Tuist that is available.
    func latestVersion() -> Single<SPMUtility.Version>
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

    func latestVersion() -> Single<SPMUtility.Version> {
        let request = GoogleCloudStorageClient.releasesRequest(path: "latest/version")
        return urlSessionScheduler.single(request: request)
            .map { data in
                if let string = String(data: data, encoding: .utf8) {
                    if let version = SPMUtility.Version(string: string) {
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
        var components = URLComponents(string: "https://storage.googleapis.com")!
        components.path = "/tuist-releases/\(path)"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        return request
    }
}
