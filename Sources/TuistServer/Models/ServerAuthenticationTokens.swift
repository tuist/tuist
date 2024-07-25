import Foundation

public struct ServerAuthenticationTokens {
    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    public let accessToken: String
    public let refreshToken: String
}
