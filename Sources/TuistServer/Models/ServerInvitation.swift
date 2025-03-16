import Foundation

/// Server invitation
public struct ServerInvitation: Codable {
    public init(
        id: Int,
        inviteeEmail: String,
        inviter: ServerUser,
        organizationId: Int,
        token: String
    ) {
        self.id = id
        self.inviteeEmail = inviteeEmail
        self.inviter = inviter
        self.organizationId = organizationId
        self.token = token
    }

    public let id: Int
    public let inviteeEmail: String
    public let inviter: ServerUser
    public let organizationId: Int
    public let token: String
}

extension ServerInvitation {
    init(_ invitation: Components.Schemas.Invitation) {
        id = Int(invitation.id)
        inviteeEmail = invitation.invitee_email
        inviter = ServerUser(invitation.inviter)
        organizationId = Int(invitation.organization_id)
        token = invitation.token
    }
}

#if MOCKING
    extension ServerInvitation {
        public static func test(
            id: Int = 0,
            inviteeEmail: String = "test@tuist.io",
            inviter: ServerUser = .test(),
            organizationId: Int = 0,
            token: String = "token"
        ) -> Self {
            .init(
                id: id,
                inviteeEmail: inviteeEmail,
                inviter: inviter,
                organizationId: organizationId,
                token: token
            )
        }
    }
#endif
