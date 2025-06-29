import Foundation
import TuistAppStorage

public enum AuthenticationState: Equatable, Codable {
    case loggedIn(accountHandle: String)
    case loggedOut
}

public struct AuthenticationStateKey: AppStorageKey {
    public static let key = "authenticationState"
    public static let defaultValue: AuthenticationState = .loggedOut
}
