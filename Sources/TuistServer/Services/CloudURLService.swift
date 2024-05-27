import Foundation
import TuistSupport

enum CloudURLServiceError: FatalError {
    case invalidCloudURL

    /// Error description.
    var description: String {
        switch self {
        case .invalidCloudURL:
            return "The cloud URL is invalid."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidCloudURL:
            return .bug
        }
    }
}

public protocol CloudURLServicing {
    func url(configCloudURL: URL?) throws -> URL
}

public final class CloudURLService: CloudURLServicing {
    public init() {}

    public func url(configCloudURL: URL?) throws -> URL {
        guard let cloudURL = ProcessInfo.processInfo.environment["TUIST_CLOUD_URL"]
            .map(URL.init(string:)) ?? configCloudURL ?? URL(string: Constants.URLs.production)
        else {
            throw CloudURLServiceError.invalidCloudURL
        }

        return cloudURL
    }
}
