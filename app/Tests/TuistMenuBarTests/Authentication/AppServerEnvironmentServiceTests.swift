import Foundation
import Mockable
import Testing
import TuistAppStorage
import TuistAuthentication
import TuistServer

@Suite struct AppServerEnvironmentServiceTests {
    @Test(arguments: [
        "", "tuist.example.com", "http://tuist.example.com", "file:///tmp/server",
        "https://", "https://user:password@tuist.example.com", "https://tuist.example.com?token=secret",
        "https://tuist.example.com#fragment", "https://tuist example.com", "https://tuist.example.com:0",
    ])
    func rejects_invalid_urls(input: String) {
        #expect(throws: AppServerConfigurationError.self) {
            try AppServerEnvironmentService.validatedURL(input)
        }
    }

    @Test func default_transport_reports_unreachable_servers() async {
        let subject = AppServerEnvironmentService(appStorage: ServerTestAppStorage())
        await #expect(throws: (any Error).self) {
            try await subject.selectServer("https://127.0.0.1:1")
        }
        #expect(subject.configuration == nil)
    }

    @Test func normalizes_urls_without_losing_port_or_base_path() throws {
        let url = try AppServerEnvironmentService.validatedURL("  https://TUIST.example.com:8443/tuist///\n")
        #expect(url.absoluteString == "https://tuist.example.com:8443/tuist")
    }

    @Test func registers_a_client_and_restores_the_server_and_oauth_client() async throws {
        let storage = ServerTestAppStorage()
        let subject = AppServerEnvironmentService(appStorage: storage) { request in
            switch request.url?.absoluteString {
            case "https://tuist.example.com:8443/tuist/.well-known/oauth-authorization-server":
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
                return Self.response(json: #"{"registration_endpoint":"https://tuist.example.com:8443/tuist/oauth2/register"}"#)
            case "https://tuist.example.com:8443/tuist/oauth2/register":
                #expect(request.httpMethod == "POST")
                let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
                #expect(body["redirect_uris"] as? [String] == ["tuist://oauth-callback"])
                #expect(body["grant_types"] as? [String] == ["authorization_code", "refresh_token"])
                #expect(body["token_endpoint_auth_method"] as? String == "none")
                return Self.response(statusCode: 201, json: #"{"client_id":"registered-client"}"#)
            default:
                Issue.record("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                throw URLError(.badURL)
            }
        }

        try await subject.selectServer("https://tuist.example.com:8443/tuist/")

        let restored = AppServerEnvironmentService(appStorage: storage)
        #expect(restored.url().absoluteString == "https://tuist.example.com:8443/tuist")
        #expect(restored.oauthClientId() == "registered-client")
        #expect(try restored.url(configServerURL: URL(string: "https://other.example.com")!) == restored.url())
    }

    @Test func switching_back_to_cloud_clears_the_custom_configuration() async throws {
        let storage = ServerTestAppStorage()
        let environment = MockServerEnvironmentServicing()
        let cloudURL = URL(string: "https://staging.tuist.dev")!
        given(environment).url().willReturn(cloudURL)
        given(environment).oauthClientId().willReturn("staging-client")
        let subject = AppServerEnvironmentService(appStorage: storage, defaultEnvironment: environment, perform: Self.server())
        try await subject.selectServer("https://tuist.example.com")
        try await subject.selectServer(nil)

        #expect(subject.configuration == nil)
        #expect(subject.url() == cloudURL)
        #expect(subject.oauthClientId() == "staging-client")
    }

    @Test(arguments: [
        "{}",
        #"{"registration_endpoint":"http://tuist.example.com/oauth2/register"}"#,
        #"{"registration_endpoint":"https://attacker.example.com/oauth2/register"}"#,
        "<html>Not found</html>",
    ])
    func invalid_metadata_does_not_replace_the_previous_server(metadata: String) async throws {
        let storage = ServerTestAppStorage()
        let original = AppServerEnvironmentService(appStorage: storage, perform: Self.server(clientID: "original-client"))
        try await original.selectServer("https://original.example.com")
        let subject = AppServerEnvironmentService(appStorage: storage, perform: Self.server(metadata: metadata))

        await #expect(throws: AppServerConfigurationError.self) {
            try await subject.selectServer("https://tuist.example.com")
        }
        #expect(subject.url().absoluteString == "https://original.example.com")
        #expect(subject.oauthClientId() == "original-client")
    }

    @Test(arguments: [
        (400, #"{"error":"invalid_client_metadata"}"#),
        (201, "{}"),
        (201, #"{"client_id":""}"#),
    ])
    func failed_registration_does_not_save_a_server(statusCode: Int, json: String) async {
        let storage = ServerTestAppStorage()
        let subject = AppServerEnvironmentService(
            appStorage: storage,
            perform: Self.server(registration: Self.response(statusCode: statusCode, json: json))
        )
        await #expect(throws: AppServerConfigurationError.self) {
            try await subject.selectServer("https://tuist.example.com")
        }
        #expect(subject.configuration == nil)
    }

    @Test func discovery_failure_does_not_save_a_server() async {
        let storage = ServerTestAppStorage()
        let subject = AppServerEnvironmentService(appStorage: storage) { _ in
            Self.response(statusCode: 404, json: #"{"registration_endpoint":"https://tuist.example.com/oauth2/register"}"#)
        }
        await #expect(throws: AppServerConfigurationError.self) {
            try await subject.selectServer("https://tuist.example.com")
        }
        #expect(subject.configuration == nil)
    }

    @Test func network_failure_does_not_save_a_server() async {
        let storage = ServerTestAppStorage()
        let subject = AppServerEnvironmentService(appStorage: storage) { _ in
            throw URLError(.cannotConnectToHost)
        }
        await #expect(throws: URLError.self) {
            try await subject.selectServer("https://tuist.example.com")
        }
        #expect(subject.configuration == nil)
    }

    @Test func signing_out_deletes_credentials_for_the_selected_server_and_remembers_it() async throws {
        let storage = ServerTestAppStorage()
        let environment = AppServerEnvironmentService(appStorage: storage, perform: Self.server())
        try await environment.selectServer("https://tuist.example.com")
        let account = Account(email: "qa@example.com", handle: "qa")
        try storage.set(AuthenticationStateKey.self, value: .loggedIn(account: account, server: environment.configuration))
        let store = MockServerCredentialsStoring()
        given(store).credentialsChanged.willReturn(AsyncStream { $0.finish() })
        given(store).delete(serverURL: .value(environment.url())).willReturn(())

        try await ServerCredentialsStore.$current.withValue(store) {
            let service = AuthenticationService(appStorage: storage)
            await service.signOut()
            #expect(service.authenticationState == .loggedOut)
            let storedState = try storage.get(AuthenticationStateKey.self)
            #expect(storedState == .loggedOut)
            #expect(service.selfHostedServerURL == "https://tuist.example.com")
        }

        verify(store).delete(serverURL: .value(environment.url())).called(1)
    }

    @Test func the_session_keeps_the_server_it_signed_in_to() async throws {
        let storage = ServerTestAppStorage()
        let environment = AppServerEnvironmentService(appStorage: storage, perform: Self.server(clientID: "session-client"))
        try await environment.selectServer("https://session.example.com")
        let account = Account(email: "qa@example.com", handle: "qa")
        try storage.set(AuthenticationStateKey.self, value: .loggedIn(account: account, server: environment.configuration))

        try await AppServerEnvironmentService(appStorage: storage, perform: Self.server(clientID: "other-client"))
            .selectServer("https://other.example.com")

        #expect(environment.url().absoluteString == "https://session.example.com")
        #expect(environment.oauthClientId() == "session-client")

        try storage.set(AuthenticationStateKey.self, value: .loggedOut)
        #expect(environment.url().absoluteString == "https://other.example.com")
    }

    @Test func tuist_hosted_sessions_ignore_a_self_hosted_selection() async throws {
        let storage = ServerTestAppStorage()
        let defaultEnvironment = MockServerEnvironmentServicing()
        let cloudURL = URL(string: "https://tuist.dev")!
        given(defaultEnvironment).url().willReturn(cloudURL)
        let environment = AppServerEnvironmentService(
            appStorage: storage,
            defaultEnvironment: defaultEnvironment,
            perform: Self.server()
        )
        try await environment.selectServer("https://tuist.example.com")
        try storage.set(AuthenticationStateKey.self, value: .loggedIn(account: Account(email: "qa@example.com", handle: "qa")))

        #expect(environment.url() == cloudURL)
    }

    @Test func decodes_sessions_saved_before_they_recorded_a_server() throws {
        let data = Data(#"{"loggedIn":{"account":{"email":"qa@example.com","handle":"qa"}}}"#.utf8)
        let state = try JSONDecoder().decode(AuthenticationState.self, from: data)
        #expect(state == .loggedIn(account: Account(email: "qa@example.com", handle: "qa"), server: nil))
    }

    @Test func signed_in_users_of_the_previous_version_stay_on_tuist_hosted() async throws {
        let storage = ServerTestAppStorage(raw: [
            AuthenticationStateKey.key: Data(#"{"loggedIn":{"account":{"email":"qa@example.com","handle":"qa"}}}"#.utf8),
        ])
        let defaultEnvironment = MockServerEnvironmentServicing()
        let cloudURL = URL(string: "https://tuist.dev")!
        given(defaultEnvironment).url().willReturn(cloudURL)
        given(defaultEnvironment).oauthClientId().willReturn("hosted-client")
        let environment = AppServerEnvironmentService(appStorage: storage, defaultEnvironment: defaultEnvironment)

        let service = AuthenticationService(serverEnvironmentService: environment, appStorage: storage)

        #expect(service.authenticationState == .loggedIn(account: Account(email: "qa@example.com", handle: "qa")))
        #expect(service.selfHostedServerURL == nil)
        #expect(environment.url() == cloudURL)
        #expect(environment.oauthClientId() == "hosted-client")
    }

    @Test func tuist_hosted_sessions_are_saved_in_the_previous_format() throws {
        let state = AuthenticationState.loggedIn(account: Account(email: "qa@example.com", handle: "qa"))
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? NSDictionary
        let previous = try JSONSerialization.jsonObject(
            with: Data(#"{"loggedIn":{"account":{"email":"qa@example.com","handle":"qa"}}}"#.utf8)
        ) as? NSDictionary
        #expect(saved == previous)
    }

    @Test func self_hosted_sessions_read_as_logged_out_by_the_previous_version() throws {
        let server = AppServerConfiguration(url: URL(string: "https://tuist.example.com")!, oauthClientID: "client")
        let state = AuthenticationState.loggedIn(account: Account(email: "qa@example.com", handle: "qa"), server: server)
        let data = try JSONEncoder().encode(state)

        #expect(try JSONDecoder().decode(AuthenticationState.self, from: data) == state)
        #expect(PreviousAuthenticationState(decodingFrom: data) == nil)
    }

    @Test func invalid_urls_are_rejected_before_discovery() async {
        let subject = AppServerEnvironmentService(appStorage: ServerTestAppStorage()) { _ in
            Issue.record("Invalid URLs must not trigger a request")
            throw URLError(.badURL)
        }
        await #expect(throws: AppServerConfigurationError.self) {
            try await subject.selectServer("http://tuist.example.com")
        }
    }

    /// A self-hosted server that serves OAuth metadata and accepts client registrations on its own origin.
    private static func server(
        metadata: String? = nil,
        clientID: String = "registered-client",
        registration: (Data, URLResponse)? = nil
    ) -> @Sendable (URLRequest) async throws -> (Data, URLResponse) {
        { request in
            if request.httpMethod == "POST" {
                return registration ?? response(statusCode: 201, json: #"{"client_id":"\#(clientID)"}"#)
            }
            let origin = "https://\(request.url?.host ?? "")"
            return response(json: metadata ?? #"{"registration_endpoint":"\#(origin)/oauth2/register"}"#)
        }
    }

    private static func response(statusCode: Int = 200, json: String) -> (Data, URLResponse) {
        (
            Data(json.utf8),
            HTTPURLResponse(
                url: URL(string: "https://tuist.example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private final class ServerTestAppStorage: AppStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]

    init(raw values: [String: Data] = [:]) {
        self.values = values
    }

    func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
        lock.lock()
        defer { lock.unlock() }
        guard let data = values[key.key] else { return key.defaultValue }
        return try JSONDecoder().decode(Key.Value.self, from: data)
    }

    func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key.key] = try JSONEncoder().encode(value)
    }
}

/// The authentication state as the previous app version declared it, with synthesized decoding.
private enum PreviousAuthenticationState: Decodable, Equatable {
    case loggedIn(account: Account)
    case loggedOut

    init?(decodingFrom data: Data) {
        guard let state = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = state
    }
}
