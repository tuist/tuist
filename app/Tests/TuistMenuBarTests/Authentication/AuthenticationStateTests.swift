import Foundation
import Testing
import TuistAuthentication
import TuistServer

@Suite struct AuthenticationStateTests {
    @Test func logged_in_state_round_trips_its_server_url() throws {
        let state = AuthenticationState.loggedIn(
            account: Account(email: "tuist@tuist.dev", handle: "tuist"),
            serverURL: URL(string: "https://custom.tuist.dev")!
        )

        let data = try JSONEncoder().encode(state)
        let decodedState = try JSONDecoder().decode(AuthenticationState.self, from: data)

        #expect(decodedState == state)
    }

    @Test func legacy_logged_in_state_uses_the_default_server_url() throws {
        let data = Data(
            #"{"loggedIn":{"account":{"email":"tuist@tuist.dev","handle":"tuist"}}}"#.utf8
        )

        let state = try JSONDecoder().decode(AuthenticationState.self, from: data)

        #expect(
            state == .loggedIn(
                account: Account(email: "tuist@tuist.dev", handle: "tuist"),
                serverURL: ServerEnvironmentService().url()
            )
        )
    }

    @Test func logged_out_state_round_trips() throws {
        let data = try JSONEncoder().encode(AuthenticationState.loggedOut)
        let state = try JSONDecoder().decode(AuthenticationState.self, from: data)

        #expect(state == .loggedOut)
    }
}
