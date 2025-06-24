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

#if canImport(TuistSupport)
    @Mockable
    public protocol ServerURLServicing {
        func url(configServerURL: URL) throws -> URL
    }
#else
    @Mockable
    public protocol ServerURLServicing {
        func url() -> URL
    }
#endif

public final class ServerURLService: ServerURLServicing {
    public init() {}

    #if canImport(TuistSupport)
        func url(configServerURL: URL) throws -> URL
    #else
        public func url() -> URL {
            return try! envVariableURL("TUIST_URL") ?? URL(string: "https://tuist.dev")!
        }
    #endif

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
