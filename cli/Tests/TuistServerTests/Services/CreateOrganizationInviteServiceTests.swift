import Foundation
import HTTPTypes
import OpenAPIRuntime
import Synchronization
import Testing
import TuistHTTP

@testable import TuistServer

struct CreateOrganizationInviteServiceTests {
    private let serverURL = URL(string: "https://tuist.example.com")!

    @Test(arguments: [false, true])
    func invites_with_default_and_explicit_roles(defaultRole: Bool) async throws {
        let transport = InvitationTransport(
            status: 200,
            json: """
            {"id":17,"invitee_email":"invitee@example.com","organization_id":29,"token":"invite-token",
             "inviter":{"id":41,"name":"inviter","email":"inviter@example.com"},
             "role":"\(defaultRole ? "user" : "viewer")"}
            """,
            requestedRole: defaultRole ? nil : "viewer"
        )

        let invitation = try await service(transport).createOrganizationInvite(
            organizationName: "acme", email: "invitee@example.com", role: defaultRole ? nil : .viewer, serverURL: serverURL
        )

        #expect(invitation.id == 17)
        #expect(invitation.organizationId == 29)
        #expect(invitation.inviter.id == 41)
        #expect(invitation.inviteeEmail == "invitee@example.com")
        #expect(invitation.token == "invite-token")
        #expect(transport.attempts == 1)
    }

    @Test(arguments: [
        (400, CreateOrganizationInviteServiceError.badRequest("message")),
        (401, .unauthorized("message")),
        (403, .forbidden("message")),
        (404, .notFound("message")),
        (429, .tooManyRequests("message")),
        (500, .unknownError(500)),
    ])
    func maps_errors_without_replaying_the_invitation(status: Int, error: CreateOrganizationInviteServiceError) async throws {
        let transport = InvitationTransport(status: status, json: #"{"message":"message"}"#)

        await #expect(throws: error) {
            try await service(transport).createOrganizationInvite(
                organizationName: "acme", email: "invitee@example.com", role: .viewer, serverURL: serverURL
            )
        }

        #expect(transport.attempts == 1)
    }

    private func service(_ transport: InvitationTransport) -> CreateOrganizationInviteService {
        CreateOrganizationInviteService(makeClient: { url in
            Client(
                serverURL: url, transport: transport,
                middlewares: [RetryMiddleware(maxRetries: 2, baseDelayMilliseconds: 0)]
            )
        })
    }
}

private final class InvitationTransport: ClientTransport, Sendable {
    let status: Int
    let json: String
    let requestedRole: String?
    private let count = Mutex(0)

    init(status: Int, json: String, requestedRole: String? = "viewer") {
        self.status = status
        self.json = json
        self.requestedRole = requestedRole
    }

    var attempts: Int { count.withLock { $0 } }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        count.withLock { $0 += 1 }
        #expect(baseURL.absoluteString == "https://tuist.example.com")
        #expect(request.method == .post)
        #expect(request.path == "/api/organizations/acme/invitations")
        #expect(operationID == "createInvitation")
        let data = try await Data(collecting: #require(body), upTo: .max)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        var expectedPayload = ["invitee_email": "invitee@example.com"]
        expectedPayload["role"] = requestedRole
        #expect(payload == expectedPayload)
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        if status == 429 { response.headerFields[.retryAfter] = "300" }
        return (response, HTTPBody(json))
    }
}
