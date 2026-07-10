import Foundation
import TuistAppStorage
import TuistServer

public struct Account: Equatable, Codable {
    public let email: String
    public let handle: String

    public init(email: String, handle: String) {
        self.email = email
        self.handle = handle
    }
}

public enum AuthenticationState: Equatable, Codable {
    case loggedIn(account: Account, serverURL: URL)
    case loggedOut

    private enum CodingKeys: String, CodingKey {
        case loggedIn
        case loggedOut
    }

    private enum LoggedInCodingKeys: String, CodingKey {
        case account
        case serverURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.loggedOut) {
            self = .loggedOut
            return
        }

        if container.contains(.loggedIn) {
            let loggedInContainer = try container.nestedContainer(
                keyedBy: LoggedInCodingKeys.self,
                forKey: .loggedIn
            )
            let account = try loggedInContainer.decode(Account.self, forKey: .account)
            let serverURL = try loggedInContainer.decodeIfPresent(URL.self, forKey: .serverURL) ??
                ServerEnvironmentService().url()
            self = .loggedIn(account: account, serverURL: serverURL)
            return
        }

        self = .loggedOut
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .loggedIn(account, serverURL):
            var loggedInContainer = container.nestedContainer(
                keyedBy: LoggedInCodingKeys.self,
                forKey: .loggedIn
            )
            try loggedInContainer.encode(account, forKey: .account)
            try loggedInContainer.encode(serverURL, forKey: .serverURL)
        case .loggedOut:
            try container.encode([String: String](), forKey: .loggedOut)
        }
    }
}

public struct AuthenticationStateKey: AppStorageKey {
    public static let key = "authenticationState"
    public static let defaultValue: AuthenticationState = .loggedOut
}
