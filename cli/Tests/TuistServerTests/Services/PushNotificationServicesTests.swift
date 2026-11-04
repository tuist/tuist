import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import TuistServer

struct PushNotificationServicesTests {
    private let serverURL = URL(string: "https://self-hosted.example.com")!

    @Test func registering_sends_the_device_and_returns_the_registration_id() async throws {
        let transport = StubTransport(status: 200, json: #"{"registration_id":"reg-1","future_field":true}"#) { request, body in
            #expect(request.method == .put)
            #expect(request.path == "/api/me/push-devices/install-1")
            let json = try #require(body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
            #expect(json == ["platform": "ios", "token": "abc", "environment": "sandbox", "name": "iPhone"])
        }

        let registrationID = try await register(transport)

        #expect(registrationID == "reg-1")
    }

    @Test(arguments: [
        ("retired", RegisterPushDeviceServiceError.retired("gone")),
        ("removed", .removed("gone")),
        // A reason added later must not make the app re-register under a new ID.
        ("archived", .removed("gone")),
    ])
    func gone_reasons_decide_whether_the_app_may_register_again(
        reason: String,
        expected: RegisterPushDeviceServiceError
    ) async throws {
        await #expect(throws: expected) {
            try await register(StubTransport(status: 410, json: #"{"message":"gone","reason":"\#(reason)"}"#))
        }
    }

    @Test func servers_without_push_support_are_reported_as_unsupported() async throws {
        // What a server without these routes answers to an `application/json` request.
        let legacy = StubTransport(status: 404, json: #"{"message":"Not Found"}"#)

        await #expect(throws: RegisterPushDeviceServiceError.unsupported) { try await register(legacy) }
        await #expect(throws: ListPushDevicesServiceError.unsupported) {
            try await ListPushDevicesService(makeClient: client(legacy)).listPushDevices(serverURL: serverURL)
        }
        await #expect(throws: GetNotificationPreferencesServiceError.unsupported) {
            try await getPreferences(legacy)
        }
        // Nothing was ever registered with such a server, so signing out must not fail.
        try await UnregisterPushDeviceService(makeClient: client(legacy))
            .unregisterPushDevice(installationID: "install-1", serverURL: serverURL)
    }

    @Test func kinds_the_server_does_not_offer_are_unsupported() async throws {
        await #expect(throws: GetNotificationPreferencesServiceError.unsupported) {
            try await getPreferences(StubTransport(status: 404, json: #"{"message":"Not found."}"#))
        }
    }

    @Test func authorization_and_server_failures_stay_errors() async throws {
        await #expect(throws: GetNotificationPreferencesServiceError.forbidden("app only")) {
            try await getPreferences(StubTransport(status: 403, json: #"{"message":"app only"}"#))
        }
        await #expect(throws: RegisterPushDeviceServiceError.tooManyRequests("slow down")) {
            try await register(StubTransport(status: 429, json: #"{"message":"slow down"}"#))
        }
        await #expect(throws: UnregisterPushDeviceServiceError.unknownError(500)) {
            try await UnregisterPushDeviceService(makeClient: client(StubTransport(status: 500, json: "{}")))
                .unregisterPushDevice(installationID: "install-1", serverURL: serverURL)
        }
    }

    @Test func project_settings_added_later_follow_the_account_without_failing_to_decode() async throws {
        let json = #"""
        {"kind":"new_preview","future_field":1,"accounts":[{"handle":"tuist","enabled":false,"projects":[
          {"handle":"ios-app","setting":"on","enabled":true},
          {"handle":"android-app","setting":"muted","enabled":false}
        ]}]}
        """#

        let preferences = try await getPreferences(StubTransport(status: 200, json: json))

        #expect(preferences == ServerNotificationPreferences(kind: "new_preview", accounts: [
            .init(handle: "tuist", enabled: false, projects: [
                .init(handle: "ios-app", setting: .on, enabled: true),
                .init(handle: "android-app", setting: .default, enabled: false),
            ]),
        ]))
    }

    @Test func following_the_account_again_sends_the_default_setting() async throws {
        let transport = StubTransport(status: 200, json: #"{"kind":"new_preview","accounts":[]}"#) { request, body in
            #expect(request.method == .put)
            #expect(request.path == "/api/me/notification-preferences/new_preview/projects/tuist/ios-app")
            let json = try #require(body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
            #expect(json == ["setting": "default"])
        }

        _ = try await UpdateProjectNotificationService(makeClient: client(transport)).updateProjectNotificationPreference(
            kind: "new_preview",
            accountHandle: "tuist",
            projectHandle: "ios-app",
            setting: .default,
            serverURL: serverURL
        )
    }

    private func register(_ transport: StubTransport) async throws -> String {
        try await RegisterPushDeviceService(makeClient: client(transport)).registerPushDevice(
            installationID: "install-1",
            token: "abc",
            environment: .sandbox,
            name: "iPhone",
            serverURL: serverURL
        )
    }

    private func getPreferences(_ transport: StubTransport) async throws -> ServerNotificationPreferences {
        try await GetNotificationPreferencesService(makeClient: client(transport))
            .getNotificationPreferences(kind: "new_preview", serverURL: serverURL)
    }

    private func client(_ transport: StubTransport) -> @Sendable (URL) -> Client {
        { Client(serverURL: $0, transport: transport) }
    }
}

private struct StubTransport: ClientTransport {
    let status: Int
    let json: String
    var inspect: @Sendable (HTTPRequest, Data?) throws -> Void = { _, _ in }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let data: Data? = if let body { try await Data(collecting: body, upTo: 1 << 20) } else { nil }
        try inspect(request, data)
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(json))
    }
}
