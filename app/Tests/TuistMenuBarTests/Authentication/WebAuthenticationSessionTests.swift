import AuthenticationServices
import Foundation
import Mockable
import Testing
import TuistAppStorage
import TuistServer

@testable import TuistAuthentication

@MainActor
struct WebAuthenticationSessionTests {
    private let url = URL(string: "https://tuist.example.com/oauth2/authorize")!
    private let callbackURL = URL(string: "tuist://oauth-callback?code=test&state=test")!

    @Test func refusing_to_start_throws_instead_of_waiting_for_a_callback() async {
        let subject = WebAuthenticationSession { _, _, completion in
            StubWebAuthenticationSession(starts: false, completion: completion)
        }
        await #expect(throws: AuthenticationError.unableToStartAuthentication) {
            try await subject.authenticate(url: url, callbackURLScheme: "tuist")
        }
    }

    @Test func session_is_retained_until_completion_and_then_released() async throws {
        weak var session: StubWebAuthenticationSession?
        let subject = WebAuthenticationSession { _, scheme, completion in
            #expect(scheme == "tuist")
            let created = StubWebAuthenticationSession(completion: completion)
            session = created
            return created
        }
        let task = Task { try await subject.authenticate(url: url, callbackURLScheme: "tuist") }
        try await waitUntil { session != nil }
        #expect(session?.presentationContextProvider != nil)
        #expect(session?.prefersEphemeralWebBrowserSession == true)
        session?.completion(callbackURL, nil)
        #expect(try await task.value == callbackURL)
        #expect(session == nil)
    }

    @Test func user_cancellation_is_silent_and_allows_retry() async throws {
        let error = NSError(
            domain: ASWebAuthenticationSessionErrorDomain,
            code: ASWebAuthenticationSessionError.canceledLogin.rawValue
        )
        let subject = WebAuthenticationSession { _, _, completion in
            StubWebAuthenticationSession(completion: completion, onStart: { completion(nil, error) })
        }
        #expect(try await subject.authenticate(url: url, callbackURLScheme: "tuist") == nil)
        #expect(try await subject.authenticate(url: url, callbackURLScheme: "tuist") == nil)
    }

    @Test(arguments: [2, 3])
    func presentation_errors_are_not_treated_as_user_cancellation(code: Int) async {
        let error = NSError(domain: ASWebAuthenticationSessionErrorDomain, code: code)
        let subject = WebAuthenticationSession { _, _, completion in
            StubWebAuthenticationSession(completion: completion, onStart: { completion(nil, error) })
        }
        do {
            _ = try await subject.authenticate(url: url, callbackURLScheme: "tuist")
            Issue.record("Expected the presentation error")
        } catch {
            #expect((error as NSError).domain == ASWebAuthenticationSessionErrorDomain)
            #expect((error as NSError).code == code)
        }
    }

    @Test func empty_completion_is_an_invalid_callback() async {
        let subject = WebAuthenticationSession { _, _, completion in
            StubWebAuthenticationSession(completion: completion, onStart: { completion(nil, nil) })
        }
        await #expect(throws: AuthenticationError.invalidCallbackURL) {
            try await subject.authenticate(url: url, callbackURLScheme: "tuist")
        }
    }

    @Test func cancelling_the_task_cancels_the_session() async throws {
        var session: StubWebAuthenticationSession?
        let subject = WebAuthenticationSession { _, _, completion in
            let created = StubWebAuthenticationSession(completion: completion)
            session = created
            return created
        }
        let task = Task { try await subject.authenticate(url: url, callbackURLScheme: "tuist") }
        try await waitUntil { session != nil }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(session?.cancelled == true)
    }

    @Test func explicit_cancellation_finishes_without_waiting_for_a_system_callback() async throws {
        var session: StubWebAuthenticationSession?
        let subject = WebAuthenticationSession { _, _, completion in
            let created = StubWebAuthenticationSession(completion: completion)
            session = created
            return created
        }
        let task = Task { try await subject.authenticate(url: url, callbackURLScheme: "tuist") }
        try await waitUntil { session != nil }
        subject.cancel()
        #expect(try await task.value == nil)
        #expect(session?.cancelled == true)
    }

    @Test func late_callbacks_from_a_failed_start_do_not_complete_the_retry() async throws {
        var sessions: [StubWebAuthenticationSession] = []
        let subject = WebAuthenticationSession { _, _, completion in
            let session = StubWebAuthenticationSession(starts: !sessions.isEmpty, completion: completion)
            sessions.append(session)
            return session
        }
        await #expect(throws: AuthenticationError.unableToStartAuthentication) {
            try await subject.authenticate(url: url, callbackURLScheme: "tuist")
        }
        let retry = Task { try await subject.authenticate(url: url, callbackURLScheme: "tuist") }
        try await waitUntil { sessions.count == 2 }
        sessions[0].completion(URL(string: "tuist://oauth-callback?code=stale"), nil)
        sessions[1].completion(callbackURL, nil)
        #expect(try await retry.value == callbackURL)
    }

    @Test func failed_start_resets_the_services_signing_in_state_and_allows_retry() async {
        let runner = WebAuthenticationSession { _, _, completion in
            StubWebAuthenticationSession(starts: false, completion: completion)
        }
        let service = makeAuthenticationService(runner: runner)
        for _ in 0 ..< 2 {
            await #expect(throws: AuthenticationError.unableToStartAuthentication) {
                try await service.signIn()
            }
            #expect(!service.isSigningIn)
            #expect(!service.isAuthenticatingInBrowser)
            #expect(service.authenticationState == .loggedOut)
        }
    }

    @Test func cancel_button_resets_the_service_without_waiting_for_the_browser() async throws {
        var session: StubWebAuthenticationSession?
        let runner = WebAuthenticationSession { _, _, completion in
            let created = StubWebAuthenticationSession(completion: completion)
            session = created
            return created
        }
        let service = makeAuthenticationService(runner: runner)
        let task = Task { try await service.signIn() }
        try await waitUntil { session != nil }
        #expect(service.isSigningIn)
        #expect(service.isAuthenticatingInBrowser)
        service.cancelBrowserSignIn()
        try await task.value
        #expect(!service.isSigningIn)
        #expect(!service.isAuthenticatingInBrowser)
        #expect(service.authenticationState == .loggedOut)
        #expect(session?.cancelled == true)
    }

    private func makeAuthenticationService(runner: WebAuthenticationSession) -> AuthenticationService {
        let storage = LoggedOutAppStorage()
        let credentials = MockServerCredentialsStoring()
        given(credentials).credentialsChanged.willReturn(AsyncStream { $0.finish() })
        return ServerCredentialsStore.$current.withValue(credentials) {
            AuthenticationService(appStorage: storage, webAuthenticationSession: runner)
        }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0 ..< 100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(predicate())
    }
}

private struct LoggedOutAppStorage: AppStoring {
    func get<Key: AppStorageKey>(_: Key.Type) throws -> Key.Value { Key.defaultValue }
    func set<Key: AppStorageKey>(_: Key.Type, value _: Key.Value) throws {}
}

@MainActor
private final class StubWebAuthenticationSession: WebAuthenticationSessionProtocol {
    weak var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
    var prefersEphemeralWebBrowserSession = false
    let completion: ASWebAuthenticationSession.CompletionHandler
    private let starts: Bool
    private let onStart: () -> Void
    private(set) var cancelled = false

    init(
        starts: Bool = true,
        completion: @escaping ASWebAuthenticationSession.CompletionHandler,
        onStart: @escaping () -> Void = {}
    ) {
        self.starts = starts
        self.completion = completion
        self.onStart = onStart
    }

    func start() -> Bool {
        onStart()
        return starts
    }

    func cancel() {
        cancelled = true
    }
}
