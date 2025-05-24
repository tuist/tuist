import Foundation
import Mockable
#if canImport(TuistSupport)
    import TuistSupport
#endif

enum ServerURLServiceError: LocalizedError, Equatable {
    case invalidEnvVariableServerURL(envVariable: String, value: String)

    var errorDescription: String? {
        switch self {
        case let .invalidEnvVariableServerURL(envVariable, value):
            return "The server environment variable '\(envVariable)' has an invalid URL value '\(value)'"
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
        return try (
            envVariableURL("TUIST_URL") ??
                envVariableURL("CIRRUS_TUIST_CACHE_URL") ?? configServerURL
        )
    }

    private func envVariableURL(_ envVariable: String) throws -> URL? {
        guard let envVariableString = Environment.current.variables[envVariable] else {
            return nil
        }
        guard let envVariableURL = URL(string: envVariableString) else {
            throw ServerURLServiceError.invalidEnvVariableServerURL(envVariable: envVariableString, value: envVariableString)
        }
        return envVariableURL
    }
}
