import Foundation
import HTTPTypes
import OpenAPIRuntime
import TestCoverageAttribution
import Testing

@testable import TuistServer

@Suite(.coverageAttribution)
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
        await #expect(throws: NotificationRulesServiceError.unsupported) {
            try await NotificationRulesService(makeClient: client(legacy)).listRules(serverURL: serverURL)
        }
        // Nothing was ever registered with such a server, so signing out must not fail.
        try await UnregisterPushDeviceService(makeClient: client(legacy))
            .unregisterPushDevice(installationID: "install-1", serverURL: serverURL)
    }

    @Test func authorization_and_server_failures_stay_errors() async throws {
        await #expect(throws: NotificationRulesServiceError.forbidden("app only")) {
            try await NotificationRulesService(makeClient: client(StubTransport(status: 403, json: #"{"message":"app only"}"#)))
                .listRules(serverURL: serverURL)
        }
        await #expect(throws: RegisterPushDeviceServiceError.tooManyRequests("slow down")) {
            try await register(StubTransport(status: 429, json: #"{"message":"slow down"}"#))
        }
        await #expect(throws: UnregisterPushDeviceServiceError.unknownError(500)) {
            try await UnregisterPushDeviceService(makeClient: client(StubTransport(status: 500, json: "{}")))
                .unregisterPushDevice(installationID: "install-1", serverURL: serverURL)
        }
    }

    @Test func creating_a_rule_sends_its_conditions_and_reads_back_the_saved_rule() async throws {
        let saved = #"""
        {"id":"rule-1","event":"preview_published","enabled":true,"projects":["tuist/ios-app"],
         "conditions":{"git_branch":{"operator":"contains","value":"release/"},"published_by":"me","future":1},
         "actions":[{"type":"push"}],"inserted_at":"2026-11-06T10:00:00Z","updated_at":"2026-11-06T10:00:00Z"}
        """#
        let transport = StubTransport(status: 201, json: saved) { request, body in
            #expect(request.method == .post)
            #expect(request.path == "/api/me/notification-rules")
            let json = try #require(body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? NSDictionary })
            #expect(json == [
                "event": "preview_published",
                "enabled": true,
                "projects": ["tuist/ios-app"],
                "conditions": ["track": ["operator": "is", "value": "beta"], "published_by": "anyone"],
                "actions": [["type": "push"]],
            ] as NSDictionary)
        }

        let rule = try await NotificationRulesService(makeClient: client(transport)).createRule(
            ServerNotificationRule(projects: ["tuist/ios-app"], track: .is("beta")),
            serverURL: serverURL
        )

        #expect(rule == ServerNotificationRule(
            id: "rule-1",
            projects: ["tuist/ios-app"],
            gitBranch: .contains("release/"),
            publishedByMe: true
        ))
    }

    @Test func updating_a_rule_leaves_its_event_out() async throws {
        let saved = #"""
        {"id":"rule-1","event":"preview_published","enabled":false,"projects":[],"conditions":{},
         "actions":[{"type":"push"}],"inserted_at":"2026-11-06T10:00:00Z","updated_at":"2026-11-06T10:00:00Z"}
        """#
        let transport = StubTransport(status: 200, json: saved) { request, body in
            #expect(request.method == .patch)
            #expect(request.path == "/api/me/notification-rules/rule-1")
            let json = try #require(body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
            #expect(json["event"] == nil)
            #expect(json["enabled"] as? Bool == false)
        }

        let rule = try await NotificationRulesService(makeClient: client(transport)).updateRule(
            ServerNotificationRule(id: "rule-1", isEnabled: false),
            serverURL: serverURL
        )

        #expect(rule.isEnabled == false)
        #expect(rule.track == nil)
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
