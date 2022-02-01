import Combine
import Foundation
import TSCUtility

public protocol GitEnvironmenting {
    /// Returns the authentication type that should be used with GitHub.
    func githubAuthentication() -> AnyPublisher<GitHubAuthentication?, Error>

    /// It returns the environment's Git credentials for GitHub.
    /// This is useful for operations such pulling newer Tuist versions from GitHub
    /// without hitting API limits.
    func githubCredentials() -> AnyPublisher<GithubCredentials?, Error>
}

public enum GitHubAuthentication: Equatable {
    /// Token-based authentication
    case token(String)

    /// Username/Password-based authentication
    case credentials(GithubCredentials)
}

public struct GithubCredentials: Equatable {
    /// GitHub password
    let username: String

    /// GitHub username
    let password: String
}

public enum GitEnvironmentError: FatalError {
    case githubCredentialsFillError(String)

    public var type: ErrorType {
        switch self {
        case .githubCredentialsFillError: return .bug
        }
    }

    public var description: String {
        switch self {
        case let .githubCredentialsFillError(message):
            return "Trying to get your environment's credentials for https://github.com failed with the following error: \(message)"
        }
    }
}

public class GitEnvironment: GitEnvironmenting {
    let environment: () -> [String: String]

    public init(environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }) {
        self.environment = environment
    }

    public func githubAuthentication() -> AnyPublisher<GitHubAuthentication?, Error> {
        let env = environment()
        if let environmentToken = env[Constants.EnvironmentVariables.githubAPIToken] {
            return .init(value: .token(environmentToken))
        } else {
            return githubCredentials().map { (credentials: GithubCredentials?) -> GitHubAuthentication? in
                credentials.map { GitHubAuthentication.credentials($0) }
            }
            .eraseToAnyPublisher()
        }
    }

    // https://github.com/Carthage/Carthage/blob/19a7f97112052394f3ecc33dac3c67e5384b7514/Source/CarthageKit/GitHub.swift#L85
    public func githubCredentials() -> AnyPublisher<GithubCredentials?, Error> {
        System.shared.publisher(
            ["/usr/bin/env", "echo", "url=https://github.com"],
            pipeTo: ["/usr/bin/env", "git", "credential", "fill"]
        )
        .mapToString()
        .collectAndMergeOutput()
        .flatMap { (output: String) -> AnyPublisher<GithubCredentials?, Error> in
            // protocol=https
            // host=github.com
            // username=pepibumur
            // password=foo
            let lines = output.split(separator: "\n")
            let values = lines.reduce(into: [String: String]()) { result, next in
                let components = next.split(separator: "=")
                guard components.count == 2 else { return }
                result[String(components.first!).spm_chomp()] = String(components.last!).spm_chomp()
            }
            guard let username = values["username"],
                  let password = values["password"] else { return AnyPublisher(value: nil) }
            return AnyPublisher(value: GithubCredentials(username: username, password: password))
        }
        .eraseToAnyPublisher()
    }
}
