import TuistAuthentication

public enum DesktopWindow: String {
    case welcome
    case main

    public init(authenticationState: AuthenticationState) {
        switch authenticationState {
        case .loggedOut: self = .welcome
        case .loggedIn: self = .main
        }
    }
}
