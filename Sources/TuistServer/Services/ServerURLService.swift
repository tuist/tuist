import Foundation
import Mockable
import TuistSupport

enum ServerURLServiceError: FatalError {
    case invalidServerURL

    /// Error description.
    var description: String {
        switch self {
        case .invalidServerURL:
            return "The server URL is invalid."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidServerURL:
            return .bug
        }
    }
}

@Mockable
public protocol ServerURLServicing {
    func url(configServerURL: URL) throws -> URL
}

public final class ServerURLService: ServerURLServicing {
    public init() {}

    public func url(configServerURL: URL) throws -> URL {
        guard let serverURL = ProcessInfo.processInfo.environment["TUIST_URL"]
            .map(URL.init(string:)) ?? configServerURL
        else {
            throw ServerURLServiceError.invalidServerURL
        }

        return serverURL
    }
}
