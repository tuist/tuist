import Foundation

public enum ProjectCASPlugin {
    public static func makeRemoteCAS(
        baseURL: URL,
        session: URLSession = URLSession(configuration: .default),
        headers: [String: String] = [:],
        projectId: String? = nil
    ) -> RemoteCAS {
        let configuration = RemoteCASConfiguration(
            baseURL: baseURL,
            session: session,
            defaultHeaders: headers,
            projectId: projectId
        )
        return RemoteCAS(configuration: configuration)
    }

    public static func makeRemoteCASFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = URLSession(configuration: .default),
        headers: [String: String] = [:]
    ) throws -> RemoteCAS {
        guard let value = environment["COMPILATION_CACHE_REMOTE_SERVICE_PATH"], !value.isEmpty else {
            throw ProjectCASPluginFactoryError.missingRemoteServicePath
        }
        guard let url = URL(string: value), url.scheme?.hasPrefix("http") == true else {
            throw ProjectCASPluginFactoryError.invalidRemoteServiceURL(value)
        }

        // Parse query parameters
        var baseURL = url
        var projectId: String?

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Extract query parameters
            let queryItems = components.queryItems ?? []

            for item in queryItems {
                switch item.name {
                case "projectId":
                    projectId = item.value
                default:
                    break
                }
            }

            // Rebuild URL without query parameters
            var cleanComponents = components
            cleanComponents.queryItems = nil
            if let cleanURL = cleanComponents.url {
                baseURL = cleanURL
            }
        }

        return makeRemoteCAS(
            baseURL: baseURL,
            session: session,
            headers: headers,
            projectId: projectId
        )
    }
}

public enum ProjectCASPluginFactoryError: Error, Equatable, CustomStringConvertible {
    case missingRemoteServicePath
    case invalidRemoteServiceURL(String)

    public var description: String {
        switch self {
        case .missingRemoteServicePath:
            return "Environment variable COMPILATION_CACHE_REMOTE_SERVICE_PATH is not set"
        case .invalidRemoteServiceURL(let value):
            return "Environment variable COMPILATION_CACHE_REMOTE_SERVICE_PATH does not contain a valid HTTP URL: \(value)"
        }
    }
}
