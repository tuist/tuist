import Combine
import Foundation
import TuistSupport

public final class MockGitEnvironment: GitEnvironmenting {
    public var invokedGithubAuthentication = false
    public var invokedGithubAuthenticationCount = 0
    public var stubbedGithubAuthenticationResult: Result<GitHubAuthentication?, Error>!

    public func githubAuthentication() -> Deferred<Future<GitHubAuthentication?, Error>> {
        invokedGithubAuthentication = true
        invokedGithubAuthenticationCount += 1
        return Deferred {
            Future { promise in
                promise(self.stubbedGithubAuthenticationResult)
            }
        }
    }

    public var invokedGithubCredentials = false
    public var invokedGithubCredentialsCount = 0
    public var stubbedGithubCredentialsResult: Result<GithubCredentials?, Error>!

    public func githubCredentials() -> Deferred<Future<GithubCredentials?, Error>> {
        invokedGithubCredentials = true
        invokedGithubCredentialsCount += 1
        return Deferred {
            Future { promise in
                promise(self.stubbedGithubCredentialsResult)
            }
        }
    }
}
