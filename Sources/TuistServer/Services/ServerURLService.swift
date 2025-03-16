import Foundation
import Mockable
import TuistSupport

enum ServerURLServiceError: FatalError, Equatable {
    case invalidEnvVariableServerURL(envVariable: String, value: String)

    /// Error description.
    var description: String {
        switch self {
        case let .invalidEnvVariableServerURL(envVariable, value):
            return "The server environment variable '\(envVariable)' has an invalid URL value '\(value)'"
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidEnvVariableServerURL:
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
        return try url(configServerURL: configServerURL, envVariables: ProcessInfo.processInfo.environment)
    }

    public func url(configServerURL: URL, envVariables: [String: String]) throws -> URL {
        return try (
            envVariableURL("TUIST_URL", envVariables: envVariables) ??
                envVariableURL(Constants.EnvironmentVariables.cirrusTuistCacheURL, envVariables: envVariables) ?? configServerURL
        )
    }

    private func envVariableURL(_ envVariable: String, envVariables: [String: String]) throws -> URL? {
        guard let envVariableString = envVariables[envVariable] else {
            return nil
        }
        guard let envVariableURL = URL(string: envVariableString) else {
            throw ServerURLServiceError.invalidEnvVariableServerURL(envVariable: envVariableString, value: envVariableString)
        }
        return envVariableURL
    }
}
