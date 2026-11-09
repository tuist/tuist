import Foundation
import Mockable
import TestCoverageAttribution
import Testing
import TuistAuthentication
import TuistServer

@testable import TuistFeatureFlags

@MainActor
@Suite(.coverageAttribution) struct FeatureFlagsTests {
    private let service = MockListFeatureFlagsServicing()
    private let alice = AuthenticationState.loggedIn(account: Account(email: "alice@tuist.dev", handle: "alice"))
    private let bob = AuthenticationState.loggedIn(account: Account(email: "bob@tuist.dev", handle: "bob"))
    private let reachableURL = URL(string: "https://tuist.dev")!
    private let failingURL = URL(string: "https://failing.tuist.dev")!
    private let server = Server()

    /// Requests to `failingURL` fail, so a test can make a later refresh fail by switching to it.
    private final class Server {
        var url = URL(string: "https://tuist.dev")!
    }

    init() {
        given(service).listFeatureFlags(serverURL: .value(failingURL))
            .willThrow(ListFeatureFlagsServiceError.unknownError(500))
    }

    private func makeSubject() -> FeatureFlags {
        FeatureFlags(service: service, serverURL: { [server] in server.url })
    }

    @Test func enables_the_flags_the_server_returns_and_ignores_unknown_ones() async {
        given(service).listFeatureFlags(serverURL: .value(reachableURL)).willReturn(["ai", "future-flag"])
        let subject = makeSubject()

        await subject.refresh(for: alice)

        #expect(subject.enabled == [.ai])
        #expect(subject.isEnabled(.ai))
    }

    @Test func keeps_the_session_flags_when_a_refresh_fails() async {
        given(service).listFeatureFlags(serverURL: .value(reachableURL)).willReturn(["ai"])
        let subject = makeSubject()
        await subject.refresh(for: alice)

        server.url = failingURL
        await subject.refresh(for: alice)

        #expect(subject.enabled == [.ai])
    }

    @Test func turns_flags_off_when_the_account_changes_even_if_the_refresh_fails() async {
        given(service).listFeatureFlags(serverURL: .value(reachableURL)).willReturn(["ai"])
        let subject = makeSubject()
        await subject.refresh(for: alice)

        server.url = failingURL
        await subject.refresh(for: bob)

        #expect(subject.enabled.isEmpty)
    }

    @Test func turns_flags_off_when_signing_out() async {
        given(service).listFeatureFlags(serverURL: .value(reachableURL)).willReturn(["ai"])
        let subject = makeSubject()
        await subject.refresh(for: alice)

        await subject.refresh(for: .loggedOut)

        #expect(subject.enabled.isEmpty)
        verify(service).listFeatureFlags(serverURL: .any).called(1)
    }
}
