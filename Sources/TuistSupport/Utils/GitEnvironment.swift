import Combine
import CombineExt
import Foundation
import TSCUtility

public protocol GitEnvironmenting {
    /// Returns the authentication type that should be used with GitHub.
    func githubAuthentication() -> Deferred<Future<GitHubAuthentication?, Error>>

    /// It returns the environment's Git credentials for GitHub.
    /// This is useful for operations such pulling newer Tuist versions from GitHub
    /// without hitting API limits.
    func githubCredentials() -> Deferred<Future<GithubCredentials?, Error>>
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

    public func githubAuthentication() -> Deferred<Future<GitHubAuthentication?, Error>> {
        return Deferred {
            Future<GitHubAuthentication?, Error> { promise in
                if let environmentToken = self.environment()[Constants.EnvironmentVariables.githubAPIToken] {
                    promise(.success(.token(environmentToken)))
                } else {
                    _ = self.githubCredentials().sink { completion in
                        if case let .failure(error) = completion {
                            promise(.failure(error))
                        }
                    } receiveValue: { credentials in
                        promise(.success(credentials.map(GitHubAuthentication.credentials)))
                    }
                }
            }
        }
    }

    // https://github.com/Carthage/Carthage/blob/19a7f97112052394f3ecc33dac3c67e5384b7514/Source/CarthageKit/GitHub.swift#L85
    public func githubCredentials() -> Deferred<Future<GithubCredentials?, Error>> {
        Deferred {
            Future<GithubCredentials?, Error> { promise in
                _ = System.shared.publisher(["echo", "url=https://github.com"], pipedToArguments: ["git", "credentials", "fill"])
                    .mapToString()
                    .flatMap { (event: SystemEvent<String>) -> AnyPublisher<GithubCredentials?, Error> in
                        switch event {
                        case let .standardError(errorString):
                            return AnyPublisher(error: GitEnvironmentError.githubCredentialsFillError(errorString))
                        case let .standardOutput(outputString):
//                            protocol=https
//                            host=github.com
//                            username=pepibumur
//                            password=foo
                            let lines = outputString.split(separator: "\n")
                            let values = lines.reduce(into: [String: String]()) { result, next in
                                let components = next.split(separator: "=")
                                guard components.count == 2 else { return }
                                result[String(components.first!).spm_chomp()] = String(components.last!).spm_chomp()
                            }
                            guard let username = values["username"], let password = values["password"] else { return AnyPublisher(value: nil) }
                            return AnyPublisher(value: GithubCredentials(username: username, password: password))
                        }
                    }
                    .sink { completion in
                        switch completion {
                        case let .failure(error): promise(.failure(error))
                        default: break
                        }
                    } receiveValue: { value in
                        promise(.success(value))
                    }
            }
        }
    }
}
