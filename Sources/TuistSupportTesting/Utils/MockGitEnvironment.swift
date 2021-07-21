import Combine
import Foundation
import TuistSupport

public final class MockGitEnvironment: GitEnvironmenting {
    public var invokedGithubAuthentication = false
    public var invokedGithubAuthenticationCount = 0
    public var stubbedGithubAuthenticationResult: Result<GitHubAuthentication?, Error>!

    public func githubAuthentication() -> AnyPublisher<GitHubAuthentication?, Error> {
        invokedGithubAuthentication = true
        invokedGithubAuthenticationCount += 1
        return .init(result: stubbedGithubAuthenticationResult)
    }

    public var invokedGithubCredentials = false
    public var invokedGithubCredentialsCount = 0
    public var stubbedGithubCredentialsResult: Result<GithubCredentials?, Error>!

    public func githubCredentials() -> AnyPublisher<GithubCredentials?, Error> {
        invokedGithubCredentials = true
        invokedGithubCredentialsCount += 1
        return .init(result: stubbedGithubCredentialsResult)
    }
}
