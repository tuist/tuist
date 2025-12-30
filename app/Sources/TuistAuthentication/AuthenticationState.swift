import Foundation
import TuistAppStorage

public struct Account: Equatable, Codable {
    public let email: String
    public let handle: String

    public init(email: String, handle: String) {
        self.email = email
        self.handle = handle
    }
}

public enum AuthenticationState: Equatable, Codable {
    case loggedIn(account: Account)
    case loggedOut
}

public struct AuthenticationStateKey: AppStorageKey {
    public static let key = "authenticationState"
    public static let defaultValue: AuthenticationState = .loggedOut
}
