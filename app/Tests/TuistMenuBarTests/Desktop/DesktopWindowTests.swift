import Foundation
import Testing
import TuistAuthentication

@testable import TuistMenuBar

struct DesktopWindowTests {
    @Test func unauthenticated_users_are_routed_to_the_welcome_window() {
        #expect(DesktopWindow(authenticationState: .loggedOut) == .welcome)
    }

    @Test(arguments: [
        nil,
        AppServerConfiguration(url: URL(string: "https://tuist.example.com")!, oauthClientID: "self-hosted-client"),
    ])
    func authenticated_users_are_routed_to_the_main_window(server: AppServerConfiguration?) {
        let account = Account(email: "tuist@tuist.dev", handle: "tuist")
        #expect(DesktopWindow(authenticationState: .loggedIn(account: account, server: server)) == .main)
    }
}
