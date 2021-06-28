import Combine
import CombineExt
import Foundation
import TSCUtility

public protocol GitEnvironmenting {
    /// It treturns the environment's Git credentials for GitHub.
    /// This is useful for operations such pulling newer Tuist versions from GitHub
    /// without hitting API limits.
    func githubCredentials() -> Deferred<Future<(username: String, password: String)?, Error>>
}

enum GitEnvironmentError: FatalError {
    case githubCredentialsFillError(String)

    var type: ErrorType {
        switch self {
        case .githubCredentialsFillError: return .bug
        }
    }

    var description: String {
        switch self {
        case let .githubCredentialsFillError(message):
            return "Trying to get your environment's credentials for https://github.com failed with the following error: \(message)"
        }
    }
}

public class GitEnvironment: GitEnvironmenting {
    // https://github.com/Carthage/Carthage/blob/19a7f97112052394f3ecc33dac3c67e5384b7514/Source/CarthageKit/GitHub.swift#L85
    public func githubCredentials() -> Deferred<Future<(username: String, password: String)?, Error>> {
        Deferred {
            Future<(username: String, password: String)?, Error> { promise in
                _ = System.shared.publisher(["echo", "url=https://github.com"], pipedToArguments: ["git", "credentials", "fill"])
                    .mapToString()
                    .flatMap { (event: SystemEvent<String>) -> AnyPublisher<(username: String, password: String)?, Error> in
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
                            return AnyPublisher(value: (username: username, password: password))
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
