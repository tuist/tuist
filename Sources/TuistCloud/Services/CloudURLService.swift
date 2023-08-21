import Foundation
import TuistSupport

enum CloudURLServiceError: FatalError {
    case invalidCloudURL(String)

    /// Error description.
    var description: String {
        switch self {
        case let .invalidCloudURL(url):
            return "The cloud URL \(url) is invalid."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidCloudURL:
            return .abort
        }
    }
}

public protocol CloudURLServicing {
    func url(serverURL: String?) throws -> URL
}

public final class CloudURLService: CloudURLServicing {
    public init() {}

    public func url(serverURL: String?) throws -> URL {
        let cloudURL = serverURL ?? Constants.tuistCloudURL
        guard let url = URL(string: cloudURL)
        else {
            throw CloudURLServiceError.invalidCloudURL(cloudURL)
        }

        return url
    }
}
