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
public protocol ServerEnvironmentServicing: Sendable {
    func url() -> URL
    func oauthClientId() -> String
    func url(configServerURL: URL) throws -> URL
}

public final class ServerEnvironmentService: ServerEnvironmentServicing {
    public init() {}

    public func url() -> URL {
        // swiftlint:disable:next force_try
        return try! envVariableURL("TUIST_URL") ?? URL(string: "https://tuist.dev")!
    }

    public func url(configServerURL: URL) throws -> URL {
        return try (
            envVariableURL("TUIST_URL") ?? configServerURL
        )
    }

    public func oauthClientId() -> String {
        #if canImport(TuistSupport)
            let variables = Environment.current.variables
        #else
            let variables = ProcessInfo.processInfo.environment
        #endif
        return variables["TUIST_OAUTH_CLIENT_ID"] ?? "b3298a92-3deb-4f5e-a526-b7ad324979b5"
    }

    private func envVariableURL(_ envVariable: String) throws -> URL? {
        #if canImport(TuistSupport)
            let variables = Environment.current.variables
        #else
            let variables = ProcessInfo.processInfo.environment
        #endif

        guard let envVariableString = variables[envVariable] else {
            return nil
        }
        guard let envVariableURL = URL(string: envVariableString) else {
            throw ServerURLServiceError.invalidEnvVariableServerURL(envVariable: envVariableString, value: envVariableString)
        }
        return envVariableURL
    }
}
