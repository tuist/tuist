import Foundation

enum AuthenticationState: Equatable, Codable {
    case loggedIn(accountHandle: String)
    case loggedOut
}

struct AuthenticationStateKey: AppStorageKey {
    static let key = "authenticationState"
    static let defaultValue: AuthenticationState = .loggedOut
}
